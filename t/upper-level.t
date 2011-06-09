{
  package DBIC::ShadowTest::Result;
  use base qw/DBIx::Class::Core/;

  #__PACKAGE__->load_components(qw(Shadow::Rels Shadow::Delta));

  # method as_delta { $self->delta_class->new($self->previous->get_inflated_columns, $self->get_inflated_columns) }

  ## add's a belongs_tos (or has_ones?) called 'next' and 'previous' pointing to the other versions for this result
  #__PACKAGE__->define_next_rel;
  #__PACKAGE__->define_previous_rel;
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
  __PACKAGE__->load_components(qw/Shadow
  /);
  #Shadow::Rels

  # add's a has_many called 'versions' pointing to the other versions for this result
  # optional args:
  # {
  #    name => 'versions',
  # }
  #__PACKAGE__->define_versions_rel;

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

  #use base qw/DBIx::Class::Shadow::DefaultChangeset/; # this adds an id and a datestamp I guess?
  use base qw/DBIx::Class::Core/; # this adds an id and a datestamp I guess?
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
  #__PACKAGE__->shadow_changeset_result( 'DBIC::ShadowTest::Result::Changeset' );

  #__PACKAGE__->register_class( Changeset => 'DBIC::ShadowTest::Changeset' );
  __PACKAGE__->register_class( Config => 'DBIC::ShadowTest::Config' );
}

use warnings;
use strict;

use Test::More;
use Test::Deep;

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

$level->update({ value => 'DEBUG' });
$level->update({ value => 'INFO' });
$level->update({ value => 'WARN' });
$level->update({ value => 'ERROR' });
$level->update({ value => 'FATAL' });
use Devel::Dwarn;

my $trace = {
  shadow_id => 2,
  shadow_stage => 2,
  shadow_timestamp => -1,
  shadow_val_id => 2,
  shadow_val_key => "log_level",
  shadow_val_value => "TRACE",
  shadowed_curpk_id => 2,
  shadowed_lifecycle => 2
};

my $debug = {
  shadow_id => 4,
  shadow_stage => 1,
  shadow_timestamp => -1,
  shadow_val_id => 2,
  shadow_val_key => "log_level",
  shadow_val_value => "DEBUG",
  shadowed_curpk_id => 2,
  shadowed_lifecycle => 2
};

my $info = {
  shadow_id => 5,
  shadow_stage => 1,
  shadow_timestamp => -1,
  shadow_val_id => 2,
  shadow_val_key => "log_level",
  shadow_val_value => "INFO",
  shadowed_curpk_id => 2,
  shadowed_lifecycle => 2
};

my $warn = {
  shadow_id => 6,
  shadow_stage => 1,
  shadow_timestamp => -1,
  shadow_val_id => 2,
  shadow_val_key => "log_level",
  shadow_val_value => "WARN",
  shadowed_curpk_id => 2,
  shadowed_lifecycle => 2
};

my $error = {
  shadow_id => 7,
  shadow_stage => 1,
  shadow_timestamp => -1,
  shadow_val_id => 2,
  shadow_val_key => "log_level",
  shadow_val_value => "ERROR",
  shadowed_curpk_id => 2,
  shadowed_lifecycle => 2
};

my $fatal = {
  shadow_id => 8,
  shadow_stage => 1,
  shadow_timestamp => -1,
  shadow_val_id => 2,
  shadow_val_key => "log_level",
  shadow_val_value => "FATAL",
  shadowed_curpk_id => 2,
  shadowed_lifecycle => 2
};

# all level versions
is_deeply(
   [
      $s->resultset('Config::Shadow')->search({
         shadow_val_id => $level->id
      }, {
         result_class => 'DBIx::Class::ResultClass::HashRefInflator'
      })->all
   ],
   [ $trace, $debug, $info, $warn, $error, $fatal ],
   'got expected versions'
);


# version X
my $version_X_rs = sub {
   $level->shadows->search(undef, {
      order_by     => 'shadow_id',
      result_class => 'DBIx::Class::ResultClass::HashRefInflator'
   })->slice($_[0] - 1)
};

is_deeply([$version_X_rs->(1)->all], [$trace], 'version(1) works');
is_deeply([$version_X_rs->(2)->all], [$debug], 'version(2) works');
is_deeply([$version_X_rs->(3)->all], [$info], 'version(3) works');
is_deeply([$version_X_rs->(4)->all], [$warn], 'version(4) works');
is_deeply([$version_X_rs->(5)->all], [$error], 'version(5) works');
is_deeply([$version_X_rs->(6)->all], [$fatal], 'version(6) works');

# after X
my $after_X_rs = sub {
   $level->shadows->search(undef, {
      order_by     => 'shadow_id',
      offset       => $_[0],
      result_class => 'DBIx::Class::ResultClass::HashRefInflator'
   })
};
is_deeply([$after_X_rs->(1)->all], [$debug, $info, $warn, $error, $fatal], 'after(1) works');
is_deeply([$after_X_rs->(2)->all], [$info, $warn, $error, $fatal], 'after(2) works');
is_deeply([$after_X_rs->(3)->all], [$warn, $error, $fatal], 'after(3) works');
is_deeply([$after_X_rs->(4)->all], [$error, $fatal], 'after(4) works');
is_deeply([$after_X_rs->(5)->all], [$fatal], 'after(5) works');
is_deeply([$after_X_rs->(6)->all], [], 'after(6) works');

# before X
my $before_X_rs = sub {
   $level->shadows->search({
      shadow_id     =>
        { '<' => $version_X_rs->($_[0])->get_column('shadow_id')->as_query },
   }, {
      order_by     => { -desc => 'shadow_id' },
      result_class => 'DBIx::Class::ResultClass::HashRefInflator'
   })
};
is_deeply([$before_X_rs->(1)->all], [], 'before(1) works');
is_deeply([$before_X_rs->(2)->all], [$trace], 'before(2) works');
is_deeply([$before_X_rs->(3)->all], [$debug, $trace], 'before(3) works');
is_deeply([$before_X_rs->(4)->all], [$info, $debug, $trace], 'before(4) works');
is_deeply([$before_X_rs->(5)->all], [$warn, $info, $debug, $trace], 'before(5) works');
is_deeply([$before_X_rs->(6)->all], [$error, $warn, $info, $debug, $trace], 'before(6) works');

#$s->changeset_do({ user => 1, session => 4, caller => 'this_would_be_dumb' }, sub {
#});

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
