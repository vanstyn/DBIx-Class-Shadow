package DBICTest::S::BaseResult;
use base qw/DBIx::Class::Core/;

# if I do not do this the update()'s in Ordered get in the way
__PACKAGE__->table('_dummy_');
__PACKAGE__->resultset_class('DBICTest::S::BaseResultSet');

# we need some attr to unambiguously identify the direction of a relation
# is_foreign_key_constraint is already taken to mean "create/do not create a
# real constraint on deploy()" so instead I am making up a new one. We need
# to agree on a name and add this to DBIC core on each helper
# ::Shadow currently refuses to shadow a relationship that does not specify
# this flag (heuristics is a dangerous thing in the case of shadowing)

sub belongs_to {
  my ($self, @args) = @_;

  $args[3] = {
    is_foreign => 1,
    on_update => 'cascade',
    on_delete => 'cascade',
    %{$args[3]||{}}
  };

  $self->next::method(@args);
}

sub has_many {
  my ($self, @args) = @_;

  $args[3] = {
    is_foreign => 0,
    cascade_rekey => 1,
    cascade_delete => 1,
    %{$args[3]||{}}
  };

  $self->next::method(@args);
}

sub might_have {
  my ($self, @args) = @_;

  $args[3] = {
    is_foreign => 0,
    cascade_rekey => 1,
    cascade_delete => 0,
    %{$args[3]||{}}
  };

  $self->next::method(@args);
}

sub has_one {
  my ($self, @args) = @_;

  $args[3] = {
    is_foreign => 0,
    cascade_rekey => 1,
    cascade_delete => 1,
    %{$args[3]||{}}
  };

  $self->next::method(@args);
}

1;
