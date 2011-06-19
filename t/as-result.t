use warnings;
use strict;

use Test::More;

use lib 't/lib';
use DBICTest::S;

my $s = DBICTest::S->connect('dbi:SQLite::memory:');

$s->deploy();

my $artist = $s->resultset('Artist')->create({ name => 'Mark Foster' });
$artist->cds->create({ title => 'Foster the People EP' });

$artist->update({ name => 'Foster The People' });
$artist->cds->create({ title => 'Torches' });

my ($v1, $v2) = $artist->shadows->all;

is $v1->as_result->name, 'Mark Foster', 'columns of version 1 are correct';
is $v2->as_result->name, 'Foster The People', 'columns of version 2 are correct';

SKIP: {
skip '"vitrual vangage" not implemented', 2;

is_deeply(
   [map $_->title, $v1->as_result->cds->all],
   ['Foster the People EP'],
   'relationships for v1 are correct',
);

is_deeply(
   [map $_->title, $v2->as_result->cds->all],
   ['Foster the People EP', 'Torches'],
   'relationships for v2 are correct',
);
}

done_testing;
