package DBIx::Class::Schema::Shadow;

use warnings;
use strict;

use base qw/DBIx::Class::Schema/;

use Try::Tiny;

use List::Util qw/first/;
use List::UtilsBy qw/sort_by/;

use namespace::clean;

__PACKAGE__->mk_group_accessors (inherited => qw/shadow_result_base_class/);
__PACKAGE__->shadow_result_base_class('DBIx::Class::Shadow::Row');

my $shadow_suffix = '::Shadow';
my $row_shadows_relname = 'shadows';
my $shadow_result_component = 'DBIx::Class::Shadow';

sub register_class {
  my ($self, $moniker, $res_class) = @_;

  if ($res_class->isa ($shadow_result_component) ) {

    my $shadow_class = $self->_gen_shadow_source($res_class);

    my $shadow_rels;
    my $requested_relationships = $res_class->shadow_relationships;

    # in essence skip any relationship we can not yet work with *unless*
    # it was specifically requested
    for my $rel (@{ $requested_relationships || [ $res_class->relationships ] }) {
      next if $rel eq $row_shadows_relname;

      $self->throw_exception("Relationship clash - 'current_version' is a generated relationship for every shadow")
        if $rel eq 'current_version';

      try {
        $self->_gen_shadow_relationship($res_class, $rel)
      } catch {
        $self->throw_exception($_) if $requested_relationships;
        #warn "$_";
      };
    }

    $self->register_class($moniker . $shadow_suffix, $shadow_class);
  }

  $self->next::method ($moniker, $res_class);
}

sub _hash_for_rel { +{ map
  {( "foreign.$_" => "self.$_[1]->{$_}" )}
  keys %{$_[1]}
}}

sub _sort_colhash {
  my ($href, @cols) = $_[1];

  for (sort_by { $href->{$_}{__source_order} } keys %{$href||{}}) {
    push @cols, $_, { %{$href->{$_}} };
    delete $cols[-1]{__source_order};
  }

  @cols;
}

sub _gen_shadow_source {
  my ($self, $res_class) = @_;

  my $shadow_class = $res_class . $shadow_suffix;

  # we may request the same shadow-generation repeatedly
  unless ($shadow_class->isa($self->shadow_result_base_class)) {

    my @pks = $res_class->primary_columns
      or $self->throw_exception('Unable to shadow sources without a primary key');

    my $res_table = $res_class->table;
    $self->throw_exception("Unable to shadow $res_class - non-scalar table names are not supported")
      if ref $res_table;

    $self->ensure_class_loaded($self->shadow_result_base_class);
    $self->inject_base($shadow_class, $self->shadow_result_base_class);
    $shadow_class->table('shadow_' . $res_table);

    my $columns_info = $res_class->columns_info;
    for (keys %$columns_info) {
      $columns_info->{$_} = {% {$columns_info->{$_}} };
      delete $columns_info->{$_}{is_auto_increment};
    }

    my $shadow_cols;
    for (@{$res_class->shadow_columns}) {
      my $inf = $columns_info->{$_} || $self->throw_exception (
        "Unable to shadow nonexistent column '$_' on $res_class"
      );
      $shadow_cols->{$_} = {
        %$inf,
        __source_order => scalar keys %$shadow_cols
      };
    }

    $shadow_class->add_columns(
      shadow_id => { data_type => 'BIGINT', is_auto_increment => 1 },
      shadow_timestamp => { data_type => 'BIGINT' }, # sprintf "%d%06d", Time::HiRes::gettimeofday()
      shadowed_lifecycle => { data_type => 'BIGINT', retrieve_on_insert => 1 },
      (map {( "shadowed_curpk_$_" => { %{$columns_info->{$_}}, is_nullable => 1 } )} @pks),
      $self->_sort_colhash( { map
        {( "shadow_val_$_" => { accessor => $_, %{$shadow_cols->{$_}} } )}
        keys %$shadow_cols
      }),
    );

    $shadow_class->set_primary_key('shadow_id');

    # linkage to shadowed source
    my $current_belongs_to = { map {( $_ => "shadowed_curpk_$_" )} @pks };

    $shadow_class->belongs_to(current_version => $res_class, $self->_hash_for_rel($current_belongs_to), {
      on_delete => 'set null', on_update => 'cascade', join_type => 'left',
    });

    $res_class->has_many($row_shadows_relname => $shadow_class, $self->_hash_for_rel({ reverse %$current_belongs_to}),
      { cascade_delete => 0 }, # FIXME - need to think what to do about cascade_copy - not clear-cut
    );
  }

  return $shadow_class
}

sub _gen_shadow_relationship {
  my ($self, $res_class, $rel) = @_;

  my $rsrc = $res_class->result_source_instance;

  my $relinfo = $rsrc->relationship_info ($rel)
    or $self->throw_exception("No such relationship '$rel' on $res_class");

  my $foreign_class = $relinfo->{class};

  $self->throw_exception("Unable to shadow requested relationship '$rel' pointing to a non-shadowed class $foreign_class")
    unless $foreign_class->isa($shadow_result_component);

  my $cond = $relinfo->{cond};

  # FIXME: it is quite possible to support more relationship types than what we
  # do here, but I have no need yet, and it is... hairy :)
  #
  # For now examine any relationship and as long as it is to/from a foreign/our PK
  # we just use the lifecycle (since each lifecycle points to a specific PK group)
  # Also note that *all* resulting relationships will be has_many's back in the
  # register_class caller, since even if CD belongs to a single artist, the artist
  # can very well have *multiple* versions (say a name change) all under the same
  # lifecycle. Use the timestamp to additionally correlate and limit the results.
  #
  # There is of course a complication - if there is a *foreign* shadow which needs
  # to hold an fk to *our* lifecycle, there is no way to ensure this shadow has
  # been in fact defined. So what we do is make sure that everything is define-able
  # on the fly. Each piece of this puzzle checks whether the previous steps of
  # defining the class, adding columns, etc have already been executed, hence the
  # relative safety of doing this as we go.

  $self->throw_exception(
    'Shadowing currently only supported for static hash-based relationship conditions, '
  . "unable to shadow '$rel' on $res_class to $foreign_class"
  ) if (ref $cond ne 'HASH');

  my $stripped_cond = { map {
    my ($fc) = $_ =~ /^foreign\.(.+)/
      or $self->throw_exception("Malformed condition foreign-part '$_' of '$rel' on $res_class");

    my ($sc) = $cond->{$_} =~ /^self\.(.+)/
      or $self->throw_exception("Malformed condition self-part '$cond->{$_}' of '$rel' on $res_class");

    ($fc => $sc);

  } keys %$cond };

  my ($our_shadow, $foreign_shadow) = map
    { $self->_gen_shadow_source($_) }
    ($res_class, $foreign_class)
  ;

  my $shadow_rel_cond;
  if (! exists $relinfo->{attrs}{is_foreign}) {
    $self->throw_exception(
      "Unable to shadow relationship '$rel' - shadowing requires an explicitly specified 'is_foreign' flag"
    );
  }
  elsif ($relinfo->{attrs}{is_foreign}) {
    $self->throw_exception(
      "Unable to shadow relationship '$rel' on $res_class to $foreign_class - "
     .'only relationships containing the entire foreign PK are currently supported'
    ) if first { ! exists $stripped_cond->{$_} } $foreign_class->primary_columns;

    # simple foreign lifecycle-based relation - add the foreign col if necessary and declare the rel
    my $foreign_id_col = 'rel_' . $foreign_shadow->table . '_lifecycle';
    my $optional_belongs_to = ($relinfo->{attrs}{join_type}||'') =~ /^left/i;

    unless ($our_shadow->has_column ($foreign_id_col)) {
      $our_shadow->add_column(
        $foreign_id_col => { data_type => 'BIGINT', is_nullable => $optional_belongs_to ? 1 : 0 }
      );
      $self->_reapply_source_prototype($our_shadow->result_source_instance);
    }

    $shadow_rel_cond = { 'foreign.shadowed_lifecycle' => "self.${foreign_id_col}" };

    # ensure that we always know whether or the belongs_to is actually there
    if ($optional_belongs_to) {
      for (values %$stripped_cond) {
        $rsrc->add_columns( ('+' . $_) => { retrieve_on_insert => 1 } );
      }
      $self->_reapply_source_prototype($rsrc);
    }
  }
  else {
    my $rev_cond = { reverse %$stripped_cond };
    $self->throw_exception(
      "Unable to shadow relationship '$rel' on $res_class to $foreign_class - "
     .'only relationships containing the entire local PK are currently supported'
    ) if first { ! exists $rev_cond->{$_} } $res_class->primary_columns;

    # simple local lifecycle-based relation - add the foreign col to the other side if necessary and declare the rel
    my $our_id_fk_col = 'rel_' . $our_shadow->table . '_lifecycle';

    unless ($foreign_shadow->has_column ($our_id_fk_col)) {
      $foreign_shadow->add_column(
        $our_id_fk_col => { data_type => 'BIGINT' }
      );
      $self->_reapply_source_prototype($foreign_shadow->result_source_instance);
    }

    $shadow_rel_cond = { "foreign.${our_id_fk_col}" => 'self.shadowed_lifecycle' };
  }

  # do not deploy any FK constraints
  $our_shadow->has_many("${rel}_shadows" => $foreign_shadow, $shadow_rel_cond, {
    is_foreign_key_constraint => 0,
    is_foreign => $relinfo->{attrs}{is_foreign},  # inherit this so we have a sense of direction
    shadows_original_relname => $rel,
  });
}

# when some changes are made to a source we want to find its
# instances and re-register them, so that the prototype changes
# get applied to the registered instances
# This does not cause inf-loops, since we overload regislter_class,
# not register_source
# However it *may* fuck up something else that hooks register_source
# as it effectively will re-execute quite a lot
sub _reapply_source_prototype {
  my ($self, $modified_source_instance) = @_;

  my $result_class = $modified_source_instance->result_class;
  for my $moniker ($self->sources) {
    if ($self->class($moniker) eq $result_class) {
      $self->unregister_source($moniker);
      $self->register_source($moniker, $modified_source_instance);
    }
  }
}

1;
