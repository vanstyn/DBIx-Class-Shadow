# -*- perl -*-

use strict;
use warnings;
use Test::More;
use lib qw(t/lib);
use Module::Runtime;
use Try::Tiny;

# Force warnings into exceptions. Needed to make sure to catch ->deploy() errors
$SIG{__WARN__} = sub { die $_ };

mkdir 't/var' unless (-d 't/var');

my $db_file = 't/var/test_sqlite.db';
my $dsn = 'dbi:SQLite:dbname=' . $db_file;

# For safety:
die "DB file '$db_file' already exists; please remove this file and try again\n"
  if(-e $db_file);


# Connect with normal, non-shadowing schema:
my $schema_class = 'TestSchema::SakilaPlain';

my @connect = ($dsn, '', '', {
  AutoCommit      => 1,
  RaiseError      => 1,
  on_connect_call => 'use_foreign_keys'
});

Module::Runtime::require_module($schema_class);
my $schema = $schema_class->connect(@connect);

is_deeply(
  [sort $schema->sources],
  [
    'Actor',
    'Address',
    'Category',
    'City',
    'Country',
    'Customer',
    'Film',
    'FilmActor',
    'FilmCategory',
    'FilmText',
    'Inventory',
    'Language',
    'Payment',
    'Rental',
    'Staff',
    'Store'
  ],
  "Expected original sources reported by schema"
);


ok( 
  (try{
    $schema->deploy(); 1
  } catch { 
    my $err = shift;
    diag("$err");
  }),
  "Deploy Plain/Original Sources only"
);


##
## TODO: Add some 'existing' data here
##


$schema->storage->dbh->disconnect;

###
###
###

# Connect again with shadowing schema:
$schema_class = 'TestSchema::Sakila';
Module::Runtime::require_module($schema_class);
$schema = $schema_class->connect(@connect);

is_deeply(
  [sort $schema->sources],
  [
    'Actor',
    'Actor::Phantom',
    'Actor::Shadow',
    'Address',
    'Address::Phantom',
    'Address::Shadow',
    'Category',
    'Category::Phantom',
    'Category::Shadow',
    'City',
    'City::Phantom',
    'City::Shadow',
    'Country',
    'Country::Phantom',
    'Country::Shadow',
    'Customer',
    'Customer::Phantom',
    'Customer::Shadow',
    'Film',
    'Film::Phantom',
    'Film::Shadow',
    'FilmActor',
    'FilmActor::Phantom',
    'FilmActor::Shadow',
    'FilmCategory',
    'FilmCategory::Phantom',
    'FilmCategory::Shadow',
    'FilmText',
    'FilmText::Phantom',
    'FilmText::Shadow',
    'Inventory',
    'Inventory::Phantom',
    'Inventory::Shadow',
    'Language',
    'Language::Phantom',
    'Language::Shadow',
    'Payment',
    'Payment::Phantom',
    'Payment::Shadow',
    'Rental',
    'Rental::Phantom',
    'Rental::Shadow',
    'Staff',
    'Staff::Phantom',
    'Staff::Shadow',
    'Store',
    'Store::Phantom',
    'Store::Shadow'
  ],
  "Expected sources with shadows/phantoms reported by schema"
);



ok( 
  (try{
    $schema->deploy_shadows(); 1
  } catch { 
    my $err = shift;
    diag("$err");
  }),
  "Deploy Shadow Sources"
);

 

##
## TODO: Verify records for existing data here
##


##
## TODO: Make some more changes and verify them here
##


$schema->storage->dbh->disconnect;
unlink $db_file;

done_testing;