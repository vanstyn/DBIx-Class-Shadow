use warnings;
use strict;

use Test::More;

use lib 't/lib';
use DBICTest::S;
use DateTime;

my $s = DBICTest::S->connect('dbi:SQLite::memory:');

$s->deploy();

my $super_epoch = sub {
   my $ns = $_[0]->nanosecond;
   $ns =~ s/^(\d\d\d).*/$1/;
   $_[0]->epoch . $ns
};

my @dt = (
  year       => 2011,
  month      => 6,
  day        => 20,
  hour       => 1,
  minute     => 21,
);

my $dt1 = DateTime->new( @dt, second => 9);
my $dt2 = DateTime->new( @dt, second => 10);
my $dt3 = DateTime->new( @dt, second => 11);
my $dt4 = DateTime->new( @dt, second => 12);
my $dt5 = DateTime->new( @dt, second => 13);
my $dt6 = DateTime->new( @dt, second => 14);

$s->{_shadow_changeset_timestamp} = $dt1->$super_epoch;
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
$s->{_shadow_changeset_timestamp} = $dt2->$super_epoch;
$level->update({ value => 'DEBUG' });
$s->{_shadow_changeset_timestamp} = $dt3->$super_epoch;
$level->update({ value => 'INFO' });
$s->{_shadow_changeset_timestamp} = $dt4->$super_epoch;
$level->update({ value => 'WARN' });
$s->{_shadow_changeset_timestamp} = $dt5->$super_epoch;
$level->update({ value => 'ERROR' });
$s->{_shadow_changeset_timestamp} = $dt6->$super_epoch;
$level->update({ value => 'FATAL' });

my $station = $s->resultset('Config')->create({ key => 'station', value => 'fail' });
$station->delete;

my $trace = {
  shadow_id => 2,
  shadow_stage => 2,
  shadow_timestamp => $dt1->$super_epoch,
  shadow_val_id => 2,
  shadow_val_key => "log_level",
  shadow_val_value => "TRACE",
  shadowed_curpk_id => 2,
  shadowed_lifecycle => 2,
  shadow_changeset_id => undef,
};

my $debug = {
  shadow_id => 4,
  shadow_stage => 1,
  shadow_timestamp => $dt2->$super_epoch,
  shadow_val_id => 2,
  shadow_val_key => "log_level",
  shadow_val_value => "DEBUG",
  shadowed_curpk_id => 2,
  shadowed_lifecycle => 2,
  shadow_changeset_id => undef,
};

my $info = {
  shadow_id => 5,
  shadow_stage => 1,
  shadow_timestamp => $dt3->$super_epoch,
  shadow_val_id => 2,
  shadow_val_key => "log_level",
  shadow_val_value => "INFO",
  shadowed_curpk_id => 2,
  shadowed_lifecycle => 2,
  shadow_changeset_id => undef,
};

my $warn = {
  shadow_id => 6,
  shadow_stage => 1,
  shadow_timestamp => $dt4->$super_epoch,
  shadow_val_id => 2,
  shadow_val_key => "log_level",
  shadow_val_value => "WARN",
  shadowed_curpk_id => 2,
  shadowed_lifecycle => 2,
  shadow_changeset_id => undef,
};

my $error = {
  shadow_id => 7,
  shadow_stage => 1,
  shadow_timestamp => $dt5->$super_epoch,
  shadow_val_id => 2,
  shadow_val_key => "log_level",
  shadow_val_value => "ERROR",
  shadowed_curpk_id => 2,
  shadowed_lifecycle => 2,
  shadow_changeset_id => undef,
};

my $fatal = {
  shadow_id => 8,
  shadow_stage => 1,
  shadow_timestamp => $dt6->$super_epoch,
  shadow_val_id => 2,
  shadow_val_key => "log_level",
  shadow_val_value => "FATAL",
  shadowed_curpk_id => 2,
  shadowed_lifecycle => 2,
  shadow_changeset_id => undef,
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

subtest '$rs->version($x)' => sub {
   my $version_X_rs = sub { $level->shadows->$hri->version($_[0]) };

   is_deeply([$version_X_rs->(1)->all], [$trace], 'version(1)');
   is_deeply([$version_X_rs->(2)->all], [$debug], 'version(2)');
   is_deeply([$version_X_rs->(3)->all], [$info],  'version(3)');
   is_deeply([$version_X_rs->(4)->all], [$warn],  'version(4)');
   is_deeply([$version_X_rs->(5)->all], [$error], 'version(5)');
   is_deeply([$version_X_rs->(6)->all], [$fatal], 'version(6)');
};

subtest '$rs->after(version => $x)' => sub {
   my $after_X_rs = sub { $level->shadows->after(version => $_[0])->$hri };
   is_deeply(
      [$after_X_rs->(1)->all],
      [$debug, $info, $warn, $error, $fatal],
      'after(1)'
   );
   is_deeply(
      [$after_X_rs->(2)->all],
      [$info, $warn, $error, $fatal],
      'after(2)'
   );
   is_deeply([$after_X_rs->(3)->all], [$warn, $error, $fatal], 'after(3)');
   is_deeply([$after_X_rs->(4)->all], [$error, $fatal], 'after(4)');
   is_deeply([$after_X_rs->(5)->all], [$fatal], 'after(5)');
   is_deeply([$after_X_rs->(6)->all], [], 'after(6)');
};

{
   subtest '$rs->after(datetime => $x)' => sub {
      my $after_X_rs = sub { $level->shadows->after(datetime => $_[0])->$hri };
      is_deeply(
         [$after_X_rs->($dt1)->all],
         [$debug, $info, $warn, $error, $fatal],
         "$dt1"
      );
      is_deeply(
         [$after_X_rs->($dt2)->all],
         [$info, $warn, $error, $fatal],
         "$dt2"
      );
      is_deeply([$after_X_rs->($dt3)->all], [$warn, $error, $fatal], "$dt3");
      is_deeply([$after_X_rs->($dt4)->all], [$error, $fatal], "$dt4");
      is_deeply([$after_X_rs->($dt5)->all], [$fatal], "$dt5");
      is_deeply([$after_X_rs->($dt6)->all], [], "$dt6");
   };

   use Devel::Dwarn;
   subtest '$rs->before(datetime => $x)' => sub {
      my $before_X_rs = sub { $level->shadows->before(datetime => $_[0])->$hri };
      is_deeply( [$before_X_rs->($dt1)->all], [], "$dt1");
      is_deeply( [$before_X_rs->($dt2)->all], [$trace], "$dt2");
      is_deeply([$before_X_rs->($dt3)->all], [$trace, $debug], "$dt3");
      is_deeply([$before_X_rs->($dt4)->all], [$trace, $debug, $info], "$dt4");
      is_deeply(
         [$before_X_rs->($dt5)->all],
         [$trace, $debug, $info, $warn],
         "$dt5"
      );
      is_deeply(
         [$before_X_rs->($dt6)->all],
         [$trace, $debug, $info, $warn, $error],
         "$dt6"
      );
   };
}

subtest '$rs->before(version => $x)' => sub {
   my $before_X_rs = sub { $level->shadows->before(version => $_[0])->$hri };
   is_deeply([$before_X_rs->(1)->all], [], 'before(1)');
   is_deeply([$before_X_rs->(2)->all], [$trace], 'before(2)');
   is_deeply([$before_X_rs->(3)->all], [$debug, $trace], 'before(3)');
   is_deeply([$before_X_rs->(4)->all], [$info, $debug, $trace], 'before(4)');
   is_deeply(
      [$before_X_rs->(5)->all],
      [$warn, $info, $debug, $trace],
      'before(5)'
   );
   is_deeply(
      [$before_X_rs->(6)->all],
      [$error, $warn, $info, $debug, $trace],
      'before(6)'
   );
};

subtest '$rs->groknik()' => sub {
   my $shadows = $level->shadows;

   is($shadows->groknik('value', 'TRACE', 'DEBUG')->count, 1);
   is($shadows->groknik('value', 'DEBUG', 'TRACE')->count, 0);
};

is_deeply([$level->shadows->inserts->$hri->all], [$trace], '$rs->inserts');
is_deeply([$level->shadows->updates->$hri->all], [$debug, $info, $warn, $error, $fatal], '$rs->updates');
is_deeply([$s->resultset('Config::Shadow')->deletes->$hri->all], [{
  shadow_id => 10,
  shadow_stage => 0,
  shadow_timestamp => $dt6->$super_epoch,
  shadow_val_id => 4,
  shadow_val_key => "station",
  shadow_val_value => "fail",
  shadowed_curpk_id => undef,
  shadowed_lifecycle => 4,
  shadow_changeset_id => undef,
}], '$rs->deletes');

subtest 'next/previous' => sub {
   my ( $r1 ) = $level->shadows->version(1)->all;
   is( $r1->value, 'TRACE', 'revision 1 is what we expect');
   my $r2 = $r1->next;
   is( $r2->value, 'DEBUG', 'revision 2 is what we expect');
   my $r1_b = $r2->previous;
   is( $r1_b->value, 'TRACE', 'previous got us back to r1');
};

SKIP: {
skip 'changesets not implemented at all yet', 2;

# note that the initial hashref is not required, it's just if you want to pass
# extra stuff
$s->changeset_do({ user => 1, session => 4 }, sub {
   # maybe the sub should get the $changeset obj passed to it?
   $level->update({ value => 'TRACE' });
   $dir->update({ value => '/home/frew/var/log' });
   $code->update({ value => '1234567890' });
});

# do changesets get generated for stuff that's not explicitly in a changeset?
# I think they should, optionally at least...?

$s->changeset_do({ user => 2, session => 5 }, sub {
   $level->update({ value => 'FATAL' });
});

my $changeset_X_rs = sub {
   $s->resultset('Config')->related_resultset('shadows')->changeset($_[0])->$hri
};
is_deeply(
   [$changeset_X_rs->(1)->all],
   [{ log_level => 'TRACE' }, { log_directory => '/home/frew/var/log' },
      { account_code => '123456789'}],
   'changeset state (1) works'
);

is_deeply(
   [$changeset_X_rs->(2)->all],
   [{ log_level => 'FATAL' }, { log_directory => '/home/frew/var/log' },
      { account_code => '123456789'}],
   'changeset state (2) works'
);
}

# other thoughts:
#   similarly, because all of their column names are different, searching with
#     mutated names is awkward and should have a nice way to do it
#

done_testing;
