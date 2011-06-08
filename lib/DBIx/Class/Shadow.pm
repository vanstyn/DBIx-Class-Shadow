package DBIx::Class::Shadow;

use warnings;
use strict;

use base qw/DBIx::Class::Relationship::Cascade::Rekey DBIx::Class::Core/;

use Time::HiRes qw/gettimeofday/;
use List::Util qw/first/;
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
  my ($self, $lifecycle) = @_;

  # we need to set our own lifecycle and also retrieve related lifecycles via
  # the main object relationships
  my $rsrc = $self->result_source;
  my $shadow_rsrc = $rsrc->related_source($shadows_rel);

  my $self_rs;
  my $new_shadow = $self->new_related($shadows_rel, {
    shadow_timestamp => $rsrc->schema->{_shadow_changeset_timestamp},
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

      $new_shadow->$local_col(
        $self
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

  my $is_top_level = !$schema->{_shadow_changeset_rows};

  local $schema->{_shadow_changeset_rows} = []
    if $is_top_level;

  my $guard = $schema->txn_scope_guard
    if $is_top_level;

  # this is so a multi-operation appears to have happened at the same time
  # (maybe this is a bad idea)
  # (( but it rocks for testing ))
  local $schema->{_shadow_changeset_timestamp} = sprintf ("%d%06d", gettimeofday())
    unless $schema->{_shadow_changeset_timestamp};

  # do the actual insert - it *may* recurse in the case of Rekey/MC - the resulting
  # shadows will accumulate in _shadow_changeset_rows, and will only insert at the end
  $self->next::method(@_);

  push @{$schema->{_shadow_changeset_rows}}, $self->_instantiate_shadow_row;

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

  my $dirtycols = {$self->get_dirty_columns};

  return $self->next::method(undef, @_)
    unless first { exists $dirtycols->{$_} } @{$self->shadow_columns};

  my $rsrc = $self->result_source;
  my $schema = $rsrc->schema;

  my $guard = $schema->txn_scope_guard;

  local $schema->{_shadow_changeset_timestamp} = sprintf ("%d%06d", gettimeofday())
    unless $schema->{_shadow_changeset_timestamp};

  # do the actual update
  $self->next::method(@_);

  $self->_instantiate_shadow_row(
    $rsrc->resultset
          ->search($self->ident_condition)
           ->search_related($shadows_rel, {}, { rows => 1 })
            ->get_column('shadowed_lifecycle')
             ->as_query
  )->insert;

  $guard->commit;

  $self;
}

# TODO (it almost works on its own anyway)
sub delete { shift->next::method(@_) }

1;
