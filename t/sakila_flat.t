# -*- perl -*-

use strict;
use warnings;
use Test::More;
#use Test::Routine::Util;
use lib qw(t/lib);

my $dsn = 'dbi:SQLite::memory:';
my $schema_class = 'TestSchema::Sakila'; #<-- from Routine::Sakila

###
###
### Flattened tests out of Routine::* to make them easier to follow
###
# This test does exactly the same thing as this one-liner in t/sakila.t

#run_tests(
#	"Tracking on the 'Sakila' example db (MySQL)", 
#	'Routine::Sakila::VerifyShadows' => {
#		test_schema_dsn => $dsn,
#	}
#);

###
###
###


###
### from Routine::Base ###
###

# Requiring a min version of SQL::Translator to make sure deployed SQLite ddl
# includes appropriate ON UPDATE and ON DELETE in CONSTRAINTS
use SQL::Translator 0.11016;
use Module::Runtime;

my @connect = ($dsn, '', '', {
  AutoCommit			=> 1,
  on_connect_call	=> 'use_foreign_keys'
});

Module::Runtime::require_module($schema_class);
my $schema = $schema_class->connect(@connect);
$schema->deploy();



###
### from Routine::Sakila ###
###

use Try::Tiny;

$schema->txn_do(sub {
  ok(
    # Remove $ret to force VOID context (needed to test Storgae::insert_bulk codepath)
    do { my $ret = $schema->resultset('Language')->populate([
      [$schema->source('Language')->columns],
      [1,'English','2006-02-15 05:02:19'],
      [2,'Italian','2006-02-15 05:02:19'],
      [3,'Japanese','2006-02-15 05:02:19'],
      [4,'Mandarin','2006-02-15 05:02:19'],
      [5,'French','2006-02-15 05:02:19'],
      [6,'German','2006-02-15 05:02:19']
    ]); 1; },
    "Populate Language rows"
  );
});

ok(
  # Remove $ret to force VOID context (needed to test Storgae::insert_bulk codepath)
  do { my $ret = $schema->resultset('Film')->populate([
    [$schema->source('Film')->columns],
    [1,'ACADEMY DINOSAUR','A Epic Drama of a Feminist And a Mad Scientist who must Battle a Teacher in The Canadian Rockies',2006,1,undef,6,'0.99',86,'20.99','PG','Deleted Scenes,Behind the Scenes','2006-02-15 05:03:42'],
[2,'ACE GOLDFINGER','A Astounding Epistle of a Database Administrator And a Explorer who must Find a Car in Ancient China',2006,1,undef,3,'4.99',48,'12.99','G','Trailers,Deleted Scenes','2006-02-15 05:03:42'],
[3,'ADAPTATION HOLES','A Astounding Reflection of a Lumberjack And a Car who must Sink a Lumberjack in A Baloon Factory',2006,2,undef,7,'2.99',50,'18.99','NC-17','Trailers,Deleted Scenes','2006-02-15 05:03:42']
  ]); 1; },
  "Populate some Film rows"
);

# --------
# This barfs because 'last_update' is not supplied, but defaults to
# the current datetime. But Shadow doesn't see this, and tries to 
# insert shadow_val_last_update last_update as NULL, which throws an 
# exception because it isn't a nullable column (which shadow duplicated
# from 'last_update')
#
# UPDATE: no longer barfs after recent fix
ok( 
  (try{
    $schema->resultset('Actor')->create({
      first_name => 'JOE', 
      last_name => 'BLOW',
    })
  } catch { 
    my $err = shift;
    diag("$err");
  }),
  "Insert an Actor row (rely on db-default for 'last_update' col)"
);

# The explicit 'last_update' cols below should not be needed, but are due
# to apparent bug in Shadow (above). Using the value '2010-09-08 07:06:05'
# in order to look conspicuous
ok( 
  $schema->resultset('Actor')->create({
    #actor_id => 1,
    last_update => '2010-09-08 07:06:05', #<-- shouldn't be needed!
    first_name => 'PENELOPE', 
    last_name => 'GUINESS',
    film_actors => [
      { 
        film_id => 1, 
        last_update => '2010-09-08 07:06:05' #<-- shouldn't be needed!
      }
    ]
  }),
  "Insert an Actor row with film_actors link"
);
#
# --------

ok(
  my $Film = $schema->resultset('Film')->search_rs({ 
    title => 'ACADEMY DINOSAUR'
  })->first,
  "Find 'ACADEMY DINOSAUR' Film row"
);

ok(
  $Film->update({
    title => 'Academy Dinosaur',
    release_year => '1812',
    length => 42
  }),
  "Make a few trivial updates to 'ACADEMY DINOSAUR' Film row"
);


ok(
  my $English = $schema->resultset('Language')->search_rs({ 
    name => 'English'
  })->first,
  "Find 'English' Language row"
);

ok(
  $English->update({ language_id => 100 }),
  "Change the PK of the 'English' Language row (should cascade)"
);



###
### from Routine::Sakila::VerifyShadows ###
###

# convenience func - gets the latest shadow row from an Rs of shadows:
sub latest_shadow($) {
  my $ShadowRs = shift;
  return $ShadowRs->search_rs(undef,
    { order_by => { -desc => 'shadow_id' } }
  )->first;
}


sub ok_matches_latest_shadow {
  my $Row = shift;
  my $test_name = shift || "Current Row ($Row) matches its most recent Shadow";
  ok(
    my $ShadowRow = latest_shadow $Row->shadows,
    " Get Shadow /for:[$test_name]"
  );
  is_deeply(
    { $ShadowRow->as_result->get_columns },
    { $Row->get_columns },
    $test_name
  );
}

ok(
  my $Language = $schema->resultset('Language')->find({ name => 'English' }),
  "Find the English Language Row"
);

ok_matches_latest_shadow(
  $Language,
  "Current 'English' Language Row matches its latest Shadow"
);

ok(
  my $FilmShadowRs = $schema->resultset('Film::Shadow'),
  "Get the Shadow ResultSet for 'Film'"
);

ok(
  $Film = $schema->resultset('Film')->find({ film_id => 1 }),
  "Find the first Film (Academy Dinosaur) Row"
);

ok(
  my $Shadows = $Film->shadows,
  "Get the first Film (Academy Dinosaur) Shadows"
);

# ---------
# This is failing, seeing 2 changes when there should be 3. It is missing
# the change that happened via db-side cascade when the ID of Language '1'
# (English) was changed to '100'. Is this a bug, or just not implemented yet?
is(
  $Shadows->count => 3, # <-- should be 3, not 2
  "Expected number of first Film (Academy Dinosaur) Shadows"
);

# This fails for the same reason as above, the change from language_id 1 to
# 100 was missed
ok_matches_latest_shadow(
  $Film,
  "Current first Film (Academy Dinosaur) Row matches its latest Shadow"
);
#
# ---------


# -- Bulk iterate and compare all our rows to their latest shadow 
# (does overlap with some more targeted tests above)
my @results = qw(Actor Film Language FilmActor);
foreach my $result (@results) {
  ok_matches_latest_shadow($_) for ($schema->resultset($result)->all);
}
# --

done_testing;