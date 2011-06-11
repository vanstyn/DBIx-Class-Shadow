use warnings;
use strict;

use Test::More;

use lib 't/lib';
use DBICTest::S;

my $s = DBICTest::S->connect('dbi:SQLite::memory:');

$s->deploy();

my $artist = $s->resultset('Artist')->create({ name => 'Mark Foster' });
$artist->update({ name => 'Foster The People' });
#$artist->delete;

my ($v1, $v2) = $s->resultset('Artist')->related_resultset('shadows')->all;

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

done_testing;

