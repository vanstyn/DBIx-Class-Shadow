use 5.008001;
use inc::Module::Install 1.00;
use strict;
use warnings;

name     'DBIx-Class-Shadow';
perl_version '5.008001';
all_from 'lib/DBIx/Class/Shadow.pm';

requires 'List::UtilsBy' => '0.07';

WriteAll;

