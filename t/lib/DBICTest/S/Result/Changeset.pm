package DBICTest::S::Result::Changeset;

use warnings;
use strict;

#use base qw/DBIx::Class::Shadow::DefaultChangeset/; # this adds an id and a datestamp I guess?
use base qw/DBICTest::S::BaseResult/;
sub new {
   my ($class, $args, @rest) = @_;

   # munge args here

   $class->next::method($args, @rest);
}

__PACKAGE__->table('changeset');

__PACKAGE__->add_columns(
  id          => { data_type => 'bigint', is_auto_increment => 1 },
  timestamp   => { data_type => 'bigint' },
  user_id     => { data_type => 'int', default_value => 0 },
  session_id  => { data_type => 'int', default_value => 0 },
  caller      => { data_type => 'varchar', length => 75 },
);

1;
