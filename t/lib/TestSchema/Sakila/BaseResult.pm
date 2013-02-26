package TestSchema::Sakila::BaseResult;
use base qw/DBIx::Class::Core/;

# if I do not do this the update()'s in Ordered get in the way
__PACKAGE__->table('_dummy_');
__PACKAGE__->resultset_class('TestSchema::Sakila::BaseResultSet');


1;
