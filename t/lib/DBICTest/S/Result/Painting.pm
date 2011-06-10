# simple non-shadowed class, make sure it does not screw anything up
package DBICTest::S::Result::Painting;

use warnings;
use strict;

use base qw/DBICTest::S::BaseResult/;

__PACKAGE__->table('paintings');

__PACKAGE__->add_columns(
  id => { data_type => 'int', is_auto_increment => 1 },
  artist_name => { data_type => 'varchar', size => 30 },
  title => { data_type => 'varchar', size => 100 },
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->belongs_to(artist => 'DBICTest::S::Result::Artist', {qw/foreign.name self.artist_name/});

1;
