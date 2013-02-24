# -*- perl -*-

use strict;
use warnings;
use Test::More;
use Test::Routine::Util;
use lib qw(t/lib);

my $dsn = 'dbi:SQLite::memory:';

#my $db_file = '/tmp/sakila.db';
#unlink $db_file if (-f $db_file);
#$dsn = 'dbi:SQLite:dbname=' . $db_file;


run_tests(
	"Tracking on the 'Sakila' example db (MySQL)", 
	'Routine::Sakila::VerifyShadows' => {
		test_schema_dsn => $dsn,
	}
);


done_testing;