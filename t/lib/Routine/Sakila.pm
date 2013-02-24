package # hide from PAUSE
     Routine::Sakila;
use strict;
use warnings;

use Test::Routine;
with 'Routine::Base';

use Test::More; 
use namespace::autoclean;
use Try::Tiny;

has 'test_schema_class', is => 'ro', default => 'TestSchema::Sakila';

test 'inserts' => { desc => 'Insert Test Data' } => sub {
	my $self = shift;
	my $schema = $self->Schema;
	
	
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

	
};



test 'simple_updates' => { desc => 'Trivial updates' } => sub {
	my $self = shift;
	my $schema = $self->Schema;
	
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

};



test 'updates_cascades' => { desc => 'Updates causing db-side cascades' } => sub {
	my $self = shift;
	my $schema = $self->Schema;
	
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
	
};	

1;