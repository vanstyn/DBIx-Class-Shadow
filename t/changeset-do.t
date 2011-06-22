use warnings;
use strict;

use Test::More;

use lib 't/lib';
use DBICTest::S;

my $s = DBICTest::S->connect('dbi:SQLite::memory:');

$s->deploy();

$s->changeset_do(sub {
   my $artist = $s->resultset('Artist')->create({ name => 'Mark Foster' });
   $artist->update({ name => 'Foster The People' });
   $artist->delete;
});

$s->changeset_do({ user_id => 2 }, sub {
   my $artist = $s->resultset('Artist')->create({ name => 'Roine Stolt' });
   $artist->update({ name => 'The Flower Kings' });
   $artist->delete;
});

my @user_ids = map $_->{user_id}, $s->resultset('Changeset')->search(undef, {
   result_class => 'DBIx::Class::ResultClass::HashRefInflator'
})->all;

is $user_ids[0], 0, 'unset user_id';
is $user_ids[1], 2, 'set user_id';

done_testing;


