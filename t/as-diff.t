use warnings;
use strict;

use Test::More;

use lib 't/lib';
use DBICTest::S;

my $s = DBICTest::S->connect('dbi:SQLite::memory:');

$s->deploy();

my $artist = $s->resultset('Artist')->create({ name => 'Mark Foster' });
$artist->update({ name => 'Foster The People' });
$artist->delete;

my ($v1, $v2, $v3) = $s->resultset('Artist::Shadow')->all;

is_deeply(
   [ $v1->as_diff ],
   [insert => undef, { name => 'Mark Foster', alias => undef }],
   'insert diff works correctly'
);

is_deeply(
   [ $v2->as_diff ],
   [update =>
      { name => 'Mark Foster', alias => undef },
      { name => 'Foster The People', alias => undef }
   ],
   'update diff works correctly'
);

is_deeply(
   [ $v3->as_diff ],
   [delete =>
      { name => 'Foster The People', alias => undef },
      undef,
   ],
   'delete diff works correctly'
);

done_testing;

