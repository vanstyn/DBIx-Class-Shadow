package DBICTest::S::Result::CD;

use warnings;
use strict;

use base qw/DBICTest::S::BaseResult/;
__PACKAGE__->load_components(qw/Shadow/);

__PACKAGE__->shadow_columns([qw/title/]); # only title changes are recorded

__PACKAGE__->table('cds');

__PACKAGE__->add_columns(
  id => { data_type => 'int', is_auto_increment => 1 },
  artist_name => { data_type => 'varchar', size => 30 },
  title => { data_type => 'varchar', size => 30 },
  single_track_cdid => { data_type => 'int', is_nullable => 1 },
  single_track_pos => { data_type => 'int', is_nullable => 1 },
);

__PACKAGE__->set_primary_key('id');
__PACKAGE__->add_unique_constraint( u_single => [qw/single_track_cdid single_track_pos/] );

__PACKAGE__->has_many(tracks => 'DBICTest::S::Result::Track', 'cd_id');

__PACKAGE__->belongs_to(artist => 'DBICTest::S::Result::Artist', {qw/foreign.name self.artist_name/});

__PACKAGE__->belongs_to(single_track => 'DBICTest::S::Result::Track', {qw/
  foreign.cd_id self.single_track_cdid
  foreign.position self.single_track_pos
/}, { join_type => 'left', on_delete => 'set null' } );

sub render { $_[0]->title }

1;

