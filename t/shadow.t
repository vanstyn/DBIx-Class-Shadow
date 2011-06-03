use lib '/home/rabbit/devel/dbic/dbgit/lib';

{
  package DBIC::ShadowTest::Result;
  use base qw/DBIx::Class::Core/;

  # we need some attr to unambiguously identify the direction of a relation
  # is_foreign_key_constraint is already taken to mean "create/do not create a
  # real constraint on deploy()" so instead I am making up a new one. We need
  # to agree on a name and add this to DBIC core on each helper
  # ::Shadow currently refuses to shadow a relationship that does not specify
  # this flag (heuristics is a dangerous thing in the case of shadowing)

  sub belongs_to {
    my ($self, @args) = @_;

    $args[3] = {
      is_foreign => 1,
      on_update => 'cascade',
      on_delete => 'cascade',
      %{$args[3]||{}}
    };

    $self->next::method(@args);
  }

  sub has_many {
    my ($self, @args) = @_;

    $args[3] = {
      is_foreign => 0,
      cascade_rekey => 1,
      %{$args[3]||{}}
    };

    $self->next::method(@args);
  }
  sub might_have {
    my ($self, @args) = @_;

    $args[3] = {
      is_foreign => 0,
      cascade_rekey => 1,
      %{$args[3]||{}}
    };

    $self->next::method(@args);
  }
  sub has_one {
    my ($self, @args) = @_;

    $args[3] = {
      is_foreign => 0,
      cascade_rekey => 1,
      %{$args[3]||{}}
    };

    $self->next::method(@args);
  }
}

{
  package DBIC::ShadowTest::Artist;

  use warnings;
  use strict;

  use base qw/DBIC::ShadowTest::Result/;
  __PACKAGE__->load_components(qw/Shadow/);

  __PACKAGE__->table('artists');

  __PACKAGE__->add_columns(
    name => { data_type => 'varchar', size => 30 },
    alias => { data_type => 'varchar', is_nullable => 1 },
  );

  __PACKAGE__->set_primary_key('name');

  __PACKAGE__->has_many(cds => 'DBIC::ShadowTest::CD', {qw/foreign.artist_name self.name/});
  __PACKAGE__->has_many(paintings => 'DBIC::ShadowTest::Painting', {qw/foreign.artist_name self.name/});
}

{
  # simple non-shadowed class, make sure it does not screw anything up
  package DBIC::ShadowTest::Painting;

  use warnings;
  use strict;

  use base qw/DBIC::ShadowTest::Result/;

  __PACKAGE__->table('paintings');

  __PACKAGE__->add_columns(
    id => { data_type => 'int', is_auto_increment => 1 },
    artist_name => { data_type => 'varchar', size => 30 },
    title => { data_type => 'varchar', size => 100 },
  );

  __PACKAGE__->set_primary_key('id');

  __PACKAGE__->belongs_to(artist => 'DBIC::ShadowTest::Artist', {qw/foreign.name self.artist_name/});
}

{
  package DBIC::ShadowTest::CD;

  use warnings;
  use strict;

  use base qw/DBIC::ShadowTest::Result/;
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

  __PACKAGE__->has_many(tracks => 'DBIC::ShadowTest::Track', 'cd_id');

  __PACKAGE__->belongs_to(artist => 'DBIC::ShadowTest::Artist', {qw/foreign.name self.artist_name/});

  __PACKAGE__->belongs_to(single_track => 'DBIC::ShadowTest::Track', {qw/
    foreign.cd_id self.single_track_cdid
    foreign.position self.single_track_pos
  /}, { join_type => 'left' } );
}

{
  package DBIC::ShadowTest::Track;

  use warnings;
  use strict;

  use base qw/DBIC::ShadowTest::Result/;
  __PACKAGE__->load_components(qw/Ordered Shadow/);

  __PACKAGE__->shadow_columns([qw/title position/]); # only title and position changes are recorded, despite composite pk

  __PACKAGE__->table('tracks');

  __PACKAGE__->add_columns(
    cd_id => { data_type => 'int' },
    title => { data_type => 'varchar', size => 30 },
    position => { data_type => 'int' },
  );

  __PACKAGE__->set_primary_key(qw/cd_id position/);

  __PACKAGE__->belongs_to(cd => 'DBIC::ShadowTest::CD', {qw/foreign.id self.cd_id/} );

  __PACKAGE__->might_have( cd_single => 'DBIC::ShadowTest::CD', {qw/
    foreign.single_track_cdid self.cd_id
    foreign.single_track_pos  self.position
  /} );

  __PACKAGE__->grouping_column('cd_id');
  __PACKAGE__->position_column('position');
}

{
  package DBIC::ShadowTest;

  use warnings;
  use strict;

  use base qw/DBIx::Class::Schema/;
  __PACKAGE__->load_components(qw/Schema::Shadow/);

  __PACKAGE__->shadow_result_base_class( 'DBIC::ShadowTest::Result' );

  __PACKAGE__->register_class( Artist => 'DBIC::ShadowTest::Artist' );
  __PACKAGE__->register_class( CD => 'DBIC::ShadowTest::CD' );
  __PACKAGE__->register_class( Track => 'DBIC::ShadowTest::Track' );
  __PACKAGE__->register_class( Painting => 'DBIC::ShadowTest::Painting' );
}

use warnings;
use strict;

use Test::More;

my $s = DBIC::ShadowTest->connect('dbi:SQLite::memory:');

use Data::Dumper::Concise;

is_deeply (
  ({ map
    {
      my $src = $s->source($_);
      $_ => { map { $_ => $src->relationship_info($_)->{cond} } $src->relationships };
    } $s->sources
  }),
  {
    'Artist' => {
      cds       => {qw/foreign.artist_name          self.name/},
      paintings => {qw/foreign.artist_name          self.name/},
      shadows   => {qw/foreign.shadowed_curpk_name  self.name/},
    },
    'Artist::Shadow' => {
      current_version => {qw/foreign.name                         self.shadowed_curpk_name/},
      cds_shadows     => {qw/foreign.rel_shadow_artists_lifecycle self.lifecycle/},
    },

    'CD' => {
      artist       => {qw/foreign.name              self.artist_name/},
      tracks       => {qw/foreign.cd_id             self.id/},
      single_track => {qw/foreign.cd_id             self.single_track_cdid
                          foreign.position          self.single_track_pos/},
      shadows      => {qw/foreign.shadowed_curpk_id self.id/},
    },
    'CD::Shadow' => {
      current_version      => {qw/foreign.id                        self.shadowed_curpk_id/},
      artist_shadows       => {qw/foreign.lifecycle                 self.rel_shadow_artists_lifecycle/},
      tracks_shadows       => {qw/foreign.rel_shadow_cds_lifecycle  self.lifecycle/},
      single_track_shadows => {qw/foreign.lifecycle                 self.rel_shadow_tracks_lifecycle/},
    },
    Painting => {
      artist => {qw/foreign.name self.artist_name/},
    },
    'Track' => {
      shadows   => {qw/foreign.shadowed_curpk_cd_id     self.cd_id
                       foreign.shadowed_curpk_position  self.position/},
      cd        => {qw/foreign.id                       self.cd_id/},
      cd_single => {qw/foreign.single_track_cdid        self.cd_id
                       foreign.single_track_pos         self.position/},
    },
    'Track::Shadow' => {
      current_version   => {qw/foreign.cd_id                        self.shadowed_curpk_cd_id
                               foreign.position                     self.shadowed_curpk_position/},
      cd_shadows        => {qw/foreign.lifecycle                    self.rel_shadow_cds_lifecycle/},
      cd_single_shadows => {qw/foreign.rel_shadow_tracks_lifecycle  self.lifecycle/},
    },
  },
  'All relationships correctly set',
);

$s->deploy();

#$s->storage->debug(1);

# add artist + painting + 2 cds + 3 tracks each
my $a_gaga = $s->resultset('Artist')->create({
  name => 'gaga',
  paintings => [{ title => 'killed this way'}],
  cds => [
    { title => 'stab', tracks => [
      { title => 'rusty spoon' },
      { title => 'crappy plunger' },
      { title => 'non-lethal umbrella' },
    ]},
    { title => 'twist', tracks => [
      { title => 'phillips' },
      { title => 'flathead' },
      { title => 'star of david' },
    ]},
  ]
});

# rename artist
$a_gaga->update({ name => 'the laaaadyyyy' });

# retitle one track
my $t_plunger = $s->resultset('Track')->find({ title => 'crappy plunger' });
$t_plunger->update({ title => 'sparkly plunger' });

# add a single based on the retitled track
$t_plunger->create_related(cd_single => { title => 'unplugged', artist => $a_gaga, tracks => [{ title => 'hardore suction' }] });

# add an extra artist with a cd with 2 tracks, with a single on last track, with one track itself
my $a_pink = $s->resultset('Artist')->create({
  name => 'pink',
  paintings => [ { title => 'pink-ponk' } ],
  cds => [{
    title => 'still a "rockstar"',
    tracks => [
      { title => 'more a cockstar' },
      { title => 'dear mr president',
        cd_single => {
          title => "barry o'bama",
          artist => { name => 'pink' },
          tracks => [{ title => 'mr 44' }],
        }
      },
    ],
  }],
});

# move each cd's first track to the end
$_->move_last for $s->resultset('Track')->search({ position => 1 });

# delete the 1st track off each cd of the 1st artist
$a_gaga->cds->search_related('tracks', { position => 1 })->delete_all;

# add aliases to artists
my $i = 1;
for ($s->resultset('Artist')->all) {
  $_->update({ alias => 'Number ' . $i++ });
}

# add a 3rd artist
my $a_snatch = $s->resultset('Artist')->create({ name => 'sneaky' });

# re-link both singles to the new artist
$s->resultset('CD')->search({ single_track_cdid => { '!=', undef } })->update_all({ artist => $a_snatch });

# change the 3rd artist name
$a_snatch->update({ name => 'very sneaky' });

# delete the other 2 artists
$s->resultset('Artist')->search({ name => { '!=', 'very sneaky' }})->delete_all;

done_testing;
