package DBIx::Class::Shadow;

use warnings;
use strict;

use base qw/DBIx::Class::Relationship::Cascade::Rekey DBIx::Class::Core/;

use List::Util qw/first/;
use Test::Deep::NoTest qw/eq_deeply/;
use namespace::clean;

__PACKAGE__->mk_group_accessors (inherited => qw/shadow_relationships _shadow_columns/);

# FIXME - probably need to get configurable
my $shadows_rel = 'shadows';

sub shadow_columns {
  my $self = shift;
  if (@_) {
    return $self->_shadow_columns(shift);
  }
  else {
    return $self->_shadow_columns || [$self->columns];
  }
}

sub _instantiate_shadow_row {
  my ($self, $stage, $lifecycle) = @_;

  $self->throw_exception('Only insertions can happen without a lifecycle value')
    if (!$lifecycle and $stage != 2);

  # we need to set our own lifecycle and also retrieve related lifecycles via
  # the main object relationships
  my $rsrc = $self->result_source;
  my $schema = $rsrc->schema;
  my $shadow_rsrc = $rsrc->related_source($shadows_rel);

  # this is so a multi-operation appears to have happened at the same time
  # (FIXME - maybe this is a bad idea???)
  # (( but it rocks for testing ))
  local $schema->{_shadow_changeset_timestamp} = $schema->shadow_timestamp
    unless $schema->{_shadow_changeset_timestamp};

  my $self_rs;
  my $new_shadow = $self->new_related($shadows_rel, {
    shadow_timestamp => $rsrc->schema->{_shadow_changeset_timestamp},
    shadow_stage => $stage,
    shadowed_lifecycle => $lifecycle || \ sprintf(
      '( SELECT COALESCE( MAX( shadowed_lifecycle ), 0 ) + 1 FROM %s)',
      $shadow_rsrc->name,
    ),
    ( map {
      my $val = $self->get_column($_);
      ("shadow_val_$_" =>
        # in case the value was *not* retrieved on insert - we need to do it
        # ourselves
        (ref $val eq 'SCALAR' or (ref $val eq 'REF' and ref $$val eq 'ARRAY'))
          ? do {
            ($self_rs ||= $rsrc->resultset->search_rs($self->ident_condition))
              ->get_column($_)
               ->as_query
          } : $val
      );
    } @{$self->shadow_columns} ),
  });

  $new_shadow->set_from_related( changeset => $schema->{_shadow_changeset_rowobj} )
    if $schema->{_shadow_changeset_rowobj};

  for my $sh_rel ($shadow_rsrc->relationships) {
    my $relinfo = $shadow_rsrc->relationship_info($sh_rel);
    if (
      $relinfo->{attrs}{is_foreign}
        and
      my $real_rel = $relinfo->{attrs}{shadows_original_relname}
    ) {
      my ($local_col, $more) = values %{$relinfo->{cond}};
      $self->throw_exception('Do not know how to handle multi-fk shadow rels')
        if $more;

      $local_col =~ s/^self\.//
        or $self->throw_exception("Unexpected relationship fk name '$local_col'");

      $new_shadow->$local_col($stage == 0
        ? $shadow_rsrc
            ->resultset
             ->search({ shadowed_lifecycle => { '=', $lifecycle } }, { rows => 1 })
              ->get_column($local_col)
               ->as_query
        : $self
            ->search_related($real_rel)
             ->search_related($shadows_rel, {}, { rows => 1 })
              ->get_column('shadowed_lifecycle')
               ->as_query
      );
    }
  }

  return $new_shadow;
}

sub insert{
  my $self = shift;
  my $rsrc = $self->result_source;
  my $schema = $rsrc->schema;

  my $guard = $schema->txn_scope_guard
    unless $schema->{_shadow_changeset_rows};

  local $schema->{_shadow_changeset_rows} = []
    if $guard;

  # do the actual insert - it *may* recurse in the case of Rekey/MC - the resulting
  # shadows will accumulate in _shadow_changeset_rows, and will only insert at the end
  $self->next::method(@_);

  push @{$schema->{_shadow_changeset_rows}}, $self->_instantiate_shadow_row(2);

  if ($guard) {
    # MC descends to create all objects first, and inserts them later, so our
    # stack is in reverse order
    $_->insert for reverse @{$schema->{_shadow_changeset_rows}};

    $guard->commit;
  }

  $self;
}

sub update {
  my $self = shift;
  my $upd = shift;
  $self->set_inflated_columns($upd) if $upd;

  my $shadowed_cols = { map { $_ => 1 } @{$self->shadow_columns} };

  my $changes = {$self->get_dirty_columns};
  my $has_trackable_changes = defined first
    { exists $changes->{$_} }
    keys %$shadowed_cols
  ;

  my $preupdate_state = { $self->get_columns }
    unless $has_trackable_changes;

  my $rsrc = $self->result_source;
  my $schema = $rsrc->schema;

  my $guard = $schema->txn_scope_guard
    unless $schema->{_shadow_changeset_rows};

  local $schema->{_shadow_changeset_rows} = []
    if $guard;

  # do the actual update (even if apparent noop)
  $self->next::method(undef, @_);

  # something could have changed during the update cascades
  if ($preupdate_state) {
    my $updated_state = {$self->get_columns};
    for my $col (keys %$updated_state) {
      if (! eq_deeply ($preupdate_state->{$col}, $updated_state->{$col}) ) {
        if ($shadowed_cols->{$col}) {
          $has_trackable_changes = 1;
          last;
        }
        else {
          $changes->{$col} = $updated_state->{$col};
        }
      }
    }
  }

  # we need to walk the relationships and see if there is a
  # change on an *unshadowed* FK (it will not change our shadow
  # stored values, but *will* change the shadow linkage)
  my $relink_update;
  unless ($has_trackable_changes) {
    REL:
    for my $rel ($rsrc->relationships) {
      my $relinfo = $rsrc->relationship_info($rel);
      if (
        $relinfo->{attrs}{is_foreign}
          and
        $relinfo->{attrs}{shadowed_by_relname}
      ) {
        my @self_cols = values %{$relinfo->{cond}};
        for (@self_cols) {
          $_ =~ s/^self\.// or $self->throw_exception(
            "Unexpected relationship fk name '$_'"
          );
          if ($changes->{$_}) {
            # so a relationship may have changed - still make
            # a shadow object, but we'll mark it for a check
            # before insertion
            $has_trackable_changes = 1;
            $relink_update = 1;
            last REL;
          }
        }
      }
    }
  };

  if ($has_trackable_changes) {
    my $sh = $self->_instantiate_shadow_row(
      ($relink_update ? -1 : 1),   # regular or internal update
      $rsrc->resultset
            ->search($self->ident_condition)
             ->search_related($shadows_rel, {}, { rows => 1 })
              ->get_column('shadowed_lifecycle')
               ->as_query
    );

    $sh->{_possibly_duplicate_shadow} = 1
      if $relink_update;

    push @{$schema->{_shadow_changeset_rows}}, $sh;
  }

  if ($guard) {
    for my $sh (reverse @{$schema->{_shadow_changeset_rows}}) {

      if ($sh->{_possibly_duplicate_shadow}) {
        # before inserting a shadow marked as possible duplicate
        # check that we don't already have the very same exact
        # values (except id/timestamp/stage) in the shadow table
        #
        # the choice of "check" is a bit odd, but this is because
        # one can not do WHERE col = (SELECT ...) when both the
        # col is NULL and the selection returns NULL
        my $new_shadow_vals = { $sh->get_columns };
        my $rsrc = $sh->result_source;
        my @check_cols = grep
          { $_ !~ /^(?: shadow_id | shadow_timestamp | shadow_stage | shadow_changeset_id )$/x }
          $rsrc->columns
        ;
        if (my @literals = grep { ref $new_shadow_vals->{$_} } @check_cols ) {

          my ($lit_vals) = $rsrc->resultset->search({}, {
            select => [ @{$new_shadow_vals}{@literals} ],
          })->cursor->all;

          @{$new_shadow_vals}{@literals} = @$lit_vals;
        }

        # if the last change recorded looks *exactly* like us - skip it
        next if (
          $rsrc->resultset->last_shadow_rs->search(
            { 'me.shadowed_lifecycle' => $new_shadow_vals->{shadowed_lifecycle} },
            { columns => \@check_cols },
          )->as_subselect_rs->search({
            map {( $_ => $new_shadow_vals->{$_} )} @check_cols
          }, { columns => $check_cols[0] })->cursor->all
        );

        # since we already know them - might as well add the values
        $sh->set_columns($new_shadow_vals);
      }

      $sh->insert;
    }
    $guard->commit;
  }

  $self;
}

sub delete {
  my $self = shift;

  my $storage_ident_cond = $self->_storage_ident_condition;
  my $rsrc = $self->result_source;

  my $guard = $rsrc->schema->txn_scope_guard;

  ### FIXME FIXME FIXME
  ### This only works because we do not have sqlite-side cascading
  ### delete() will not be called on rows that are deleted by rdbms
  ### side triggers, we need to walk the tree ourselves *before*
  ### we issue the 1st delete
  ### Even then - if we do not shadow a particular "master" table
  ### the rdbms-side cascade will go all the way and this code
  ### won't be called at all. Not sure what's sensible...
  # "deleted" shadow - do it before it is "disappeared"
  $self->_instantiate_shadow_row(
    0,
    $rsrc->resultset
      ->search($self->_storage_ident_condition) # object may be dirty
       ->search_related($shadows_rel, {}, { rows => 1 })
        ->get_column('shadowed_lifecycle')
         ->as_query
  )->insert;

  $self->next::method(@_);

  $guard->commit;

  $self;
}

1;

=head1 NAME

DBIx::Class::Shadow - Flexible database auditing for the Perl ORM

=head1 SYNOPSIS

Add the schema component:

 package MyApp::Schema;

 use strict;
 use warnings;

 use base 'DBIx::Class::Schema';

 __PACKAGE__->load_components('Schema::Shadow');

 __PACKAGE__->load_namespaces;

 1;

Add a result component:

 package MyApp::Schema::Result::Artist;

 use warnings;
 use strict;

 use base 'DBIx::Class::Core';
 __PACKAGE__->load_components('Shadow');

 ...

 1;

=head1 DESCRIPTION

C<DBIx::Class::Shadow> is a tool for auditing your database.  It can be used as
a security measure to see who changed what and when, or it could be used as a
safety harness if single transactions ever need to be rolled back.

Note that this class specifically is for setting up shadowing per result.  To
see the schema level configuration, see L<DBIx::Class::Schema::Shadow>.

=head1 METHODS

=head2 shadow_columns

 __PACKAGE__->shadow_columns([qw( id name )]);

C<shadow_columns> allows you to set which columns to audit.  The default is all
of the columns.

=cut
