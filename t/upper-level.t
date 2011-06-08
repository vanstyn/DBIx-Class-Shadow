{
  package DBIC::ShadowTest::Result;
  use base qw/DBIx::Class::Core/;

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
      %{$args[3]||{}}
    };

    $self->next::method(@args);
  }
  sub might_have {
    my ($self, @args) = @_;

    $args[3] = {
      is_foreign => 0,
      cascade_rekey => 1,
      %{$args[3]||{}}
    };

    $self->next::method(@args);
  }
  sub has_one {
    my ($self, @args) = @_;

    $args[3] = {
      is_foreign => 0,
      cascade_rekey => 1,
      %{$args[3]||{}}
    };

    $self->next::method(@args);
  }
}

{
  package DBIC::ShadowTest::Config;

  use warnings;
  use strict;

  use base qw/DBIC::ShadowTest::Result/;
  __PACKAGE__->load_components(qw/Shadow Shadow::Rels/);

  # add's a has_many called 'versions' pointing to the other versions for this result
  # optional args:
  # {
  #    name => 'versions',
  # }
  __PACKAGE__->define_versions_rel;

  __PACKAGE__->shadow_columns([qw/id key value/]);

  __PACKAGE__->table('config');

  __PACKAGE__->add_columns(
    id  => {
      data_type => 'int',
      is_auto_increment => 1,
    },
    key => {
      data_type => 'varchar',
      length    => 25,
    },
    value => {
      data_type => 'varchar',
      length    => 25,
    },
  );

  __PACKAGE__->set_primary_key(qw/id/);
  __PACKAGE__->add_unique_constraint(['key']);
}

{
  package DBIC::ShadowTest::Result::Changeset;

  use warnings;
  use strict;

  use base qw/DBIx::Class::Shadow::DefaultChangeset/; # this adds an id and a datestamp I guess?
  sub new {
     my ($class, $args, @rest) = @_;

     # munge args here

     $class->next::method($args, @rest);
  }

  __PACKAGE__->table('changeset');

  __PACKAGE__->add_columns(
    user_id     => { data_type => 'int', default_value => 0 },
    session_id  => { data_type => 'int', default_value => 0 },
    caller      => { data_type => 'varchar', length => 75 },
  );
}

{
  package DBIC::ShadowTest;

  use warnings;
  use strict;

  use base qw/DBIx::Class::Schema/;
  __PACKAGE__->load_components(qw/Schema::Shadow/);

  __PACKAGE__->shadow_result_base_class( 'DBIC::ShadowTest::Result' );
  __PACKAGE__->shadow_changeset_result( 'DBIC::ShadowTest::Result::Changeset' );

  __PACKAGE__->register_class( Changeset => 'DBIC::ShadowTest::Changeset' );
  __PACKAGE__->register_class( Config => 'DBIC::ShadowTest::Config' );
}

use warnings;
use strict;

use Test::More;

my $s = DBIC::ShadowTest->connect('dbi:SQLite::memory:');

$s->deploy();

$s->resultset('Config')->create($_) for ({
   key => 'log_directory', value => '/var/log/MyApp',
}, {
   key => 'log_level', value => 'TRACE',
}, {
   key => 'account_code', value => 'none',
});

my $level = $s->resultset('Config')->single({ key => 'log_level' });

$s->changeset_do({ user => 1, session => 4, caller => 'this_would_be_dumb' }, sub {
   $level->update({ value => 'DEBUG' });
});

# shadow resultset methods:
#   before
#     Takes datetime object or a string
#     reverse sort
#   after
#     Takes datetime object or a string
#
#   next
#     Takes an int and defaults to 1
#   previous
#     Takes an int and defaults to 1
#     reverses sort

done_testing;
