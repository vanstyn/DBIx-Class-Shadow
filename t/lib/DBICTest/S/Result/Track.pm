package DBICTest::S::Result::Track;

use warnings;
use strict;

use base qw/DBICTest::S::BaseResult/;
__PACKAGE__->load_components(qw/Ordered Shadow/);

__PACKAGE__->shadow_columns([qw/title position/]); # only title and position changes are recorded, despite composite pk

__PACKAGE__->table('tracks');

__PACKAGE__->add_columns(
  cd_id => { data_type => 'int' },
  title => { data_type => 'varchar', size => 30 },
  position => { data_type => 'int' },
);

__PACKAGE__->set_primary_key(qw/cd_id position/);

__PACKAGE__->belongs_to(cd => 'DBICTest::S::Result::CD', {qw/foreign.id self.cd_id/} );

__PACKAGE__->might_have( cd_single => 'DBICTest::S::Result::CD', {qw/
  foreign.single_track_cdid self.cd_id
  foreign.single_track_pos  self.position
/} );

__PACKAGE__->grouping_column('cd_id');
__PACKAGE__->position_column('position');

1;
