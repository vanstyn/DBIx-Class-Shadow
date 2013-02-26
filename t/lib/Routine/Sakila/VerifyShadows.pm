package # hide from PAUSE
     Routine::Sakila::VerifyShadows;
use strict;
use warnings;

use Test::Routine;
with 'Routine::Sakila';

use Test::More; 
use namespace::autoclean;

use TestUtil;

test 'shadow_rows' => { desc => 'Verify Shadow Rows' } => sub {
	my $self = shift;
	my $schema = $self->Schema;
	
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
		my $Film = $schema->resultset('Film')->find({ film_id => 1 }),
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

};


test 'iterate_latests' => { desc => 'Bulk iterate and compare rows to their latest shadow' } => sub {
	my $self = shift;
	my $schema = $self->Schema;

	# -- Bulk iterate and compare all our rows to their latest shadow 
	# (does overlap with some more targeted tests above)
	my @results = qw(Actor Film Language FilmActor);
	foreach my $result (@results) {
		ok_matches_latest_shadow($_) for ($schema->resultset($result)->all);
	}
	# --

};

1;