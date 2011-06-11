use warnings;
use strict;

use Test::More;
use Test::Deep;

use lib 't/lib';
use DBICTest::S;

my $s = DBICTest::S->connect('dbi:SQLite::memory:');

$s->deploy();

$s->resultset('Config')->create($_) for ({
   key => 'log_directory', value => '/var/log/MyApp',
}, {
   key => 'log_level', value => 'TRACE',
}, {
   key => 'account_code', value => 'none',
});

my $level = $s->resultset('Config')->single({ key => 'log_level' });
my $dir = $s->resultset('Config')->single({ key => 'log_directory' });
my $code = $s->resultset('Config')->single({ key => 'account_code' });

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

my $hri = sub {
  $_[0]->search(undef, {
    result_class => 'DBIx::Class::ResultClass::HashRefInflator'
  })
};

# version X
my $version_X_rs = sub { $level->shadows->$hri->version($_[0]) };

is_deeply([$version_X_rs->(1)->all], [$trace], 'version(1) works');
is_deeply([$version_X_rs->(2)->all], [$debug], 'version(2) works');
is_deeply([$version_X_rs->(3)->all], [$info], 'version(3) works');
is_deeply([$version_X_rs->(4)->all], [$warn], 'version(4) works');
is_deeply([$version_X_rs->(5)->all], [$error], 'version(5) works');
is_deeply([$version_X_rs->(6)->all], [$fatal], 'version(6) works');

# after X
my $after_X_rs = sub { $level->shadows->after($_[0])->$hri };
is_deeply([$after_X_rs->(1)->all], [$debug, $info, $warn, $error, $fatal], 'after(1) works');
is_deeply([$after_X_rs->(2)->all], [$info, $warn, $error, $fatal], 'after(2) works');
is_deeply([$after_X_rs->(3)->all], [$warn, $error, $fatal], 'after(3) works');
is_deeply([$after_X_rs->(4)->all], [$error, $fatal], 'after(4) works');
is_deeply([$after_X_rs->(5)->all], [$fatal], 'after(5) works');
is_deeply([$after_X_rs->(6)->all], [], 'after(6) works');

# before X
my $before_X_rs = sub { $level->shadows->before($_[0])->$hri };
is_deeply([$before_X_rs->(1)->all], [], 'before(1) works');
is_deeply([$before_X_rs->(2)->all], [$trace], 'before(2) works');
is_deeply([$before_X_rs->(3)->all], [$debug, $trace], 'before(3) works');
is_deeply([$before_X_rs->(4)->all], [$info, $debug, $trace], 'before(4) works');
is_deeply([$before_X_rs->(5)->all], [$warn, $info, $debug, $trace], 'before(5) works');
is_deeply([$before_X_rs->(6)->all], [$error, $warn, $info, $debug, $trace], 'before(6) works');

SKIP: {
skip 'changesets not implemented at all yet', 2;

# note that the initial hashref is not required, it's just if you want to pass extra stuff
$s->changeset_do({ user => 1, session => 4 }, sub {
   # maybe the sub should get the $changeset obj passed to it?
   $level->update({ value => 'TRACE' });
   $dir->update({ value => '/home/frew/var/log' });
   $code->update({ value => '1234567890' });
});

# do changesets get generated for stuff that's not explicitly in a changeset?  I think they should, optionally at least...?

$s->changeset_do({ user => 2, session => 5 }, sub {
   $level->update({ value => 'FATAL' });
});

is_deeply([$s->resultset('Config')
   ->related_resultset('shadow')
   ->search({
      changeset_id => { '<=' => 1 },
   }, {
      # I think there needs to be some group by and having stuff to only get the newest
      # of each shadow
      result_class => 'DBIx::Class::ResultClass::HashRefInflator'
   })], [{ log_level => 'TRACE' }, { log_directory => '/home/frew/var/log' }, { account_code => '123456789'}],
   'changeset state (1) works');

is_deeply([$s->resultset('Config')
   ->related_resultset('shadow')
   ->search({
      changeset_id => { '<=' => 1 },
   }, {
      # I think there needs to be some group by and having stuff to only get the newest
      # of each shadow
      result_class => 'DBIx::Class::ResultClass::HashRefInflator'
   })], [{ log_level => 'FATAL' }, { log_directory => '/home/frew/var/log' }, { account_code => '123456789'}],
   'changeset state (2) works');
}

# other thoughts:
#   currently the shadows are quite different from their actual counterparts, we should offer a simple way
#     to rebless them into their original row or *something*
#
#   similarly, because all of their column names are different, searching with mutated names is awkward and
#     should have a nice way to do it
#
# things I need to do:
#   work on some of the shadow components:
#    * the one that defines the next and previous *relationships*
#    * as_delta

done_testing;
