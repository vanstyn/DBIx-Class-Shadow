{
  package DBIC::ShadowTest::Result;
  use base qw/DBIx::Class::Core/;

  # if I do not do this the update()'s in Ordered get in the way
  __PACKAGE__->table('_dummy_');
  __PACKAGE__->resultset_class('DBIC::ShadowTest::ResultSet');

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
      cascade_delete => 1,
      %{$args[3]||{}}
    };

    $self->next::method(@args);
  }
  sub might_have {
    my ($self, @args) = @_;

    $args[3] = {
      is_foreign => 0,
      cascade_rekey => 1,
      cascade_delete => 0,
      %{$args[3]||{}}
    };

    $self->next::method(@args);
  }
  sub has_one {
    my ($self, @args) = @_;

    $args[3] = {
      is_foreign => 0,
      cascade_rekey => 1,
      cascade_delete => 1,
      %{$args[3]||{}}
    };

    $self->next::method(@args);
  }
}

{
  package DBIC::ShadowTest::ResultSet;

  use base qw/DBIx::Class::ResultSet/;

  sub update { shift->update_all(@_) };
  sub delete { shift->delete_all(@_) };
  sub populate {
    if (defined wantarray) {
      return shift->populate(@_)
    }
    else {
      my $res = shift->populate(@_);
      return;
    }
  }
}

{
  package DBIC::ShadowTest::ShadowResult;

  use base qw/DBIC::ShadowTest::Result DBIx::Class::Shadow::Result/;
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
  /}, { join_type => 'left', on_delete => 'set null' } );
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

  __PACKAGE__->shadow_result_base_class( 'DBIC::ShadowTest::ShadowResult' );

  __PACKAGE__->register_class( Artist => 'DBIC::ShadowTest::Artist' );
  __PACKAGE__->register_class( CD => 'DBIC::ShadowTest::CD' );
  __PACKAGE__->register_class( Track => 'DBIC::ShadowTest::Track' );
  __PACKAGE__->register_class( Painting => 'DBIC::ShadowTest::Painting' );
}

use warnings;
use strict;

use Test::More;

my $s = DBIC::ShadowTest->connect('dbi:SQLite::memory:');

is_deeply (
  ({ map
    {
      my $src = $s->source($_);
      $_ => { map
        { $_ => ref ($src->relationship_info($_)->{cond}) eq 'CODE'
          ? '_CUSTOM_'
          : $src->relationship_info($_)->{cond}
        }
        $src->relationships
      };
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
      older_shadows   => '_CUSTOM_',
      newer_shadows   => '_CUSTOM_',
      cds_shadows     => {qw/foreign.rel_shadow_artists_lifecycle self.shadowed_lifecycle/},
    },

    'CD' => {
      artist       => {qw/foreign.name              self.artist_name/},
      tracks       => {qw/foreign.cd_id             self.id/},
      single_track => {qw/foreign.cd_id             self.single_track_cdid
                          foreign.position          self.single_track_pos/},
      shadows      => {qw/foreign.shadowed_curpk_id self.id/},
    },
    'CD::Shadow' => {
      current_version       => {qw/foreign.id                        self.shadowed_curpk_id/},
      older_shadows         => '_CUSTOM_',
      newer_shadows         => '_CUSTOM_',
      artist_shadows        => {qw/foreign.shadowed_lifecycle        self.rel_shadow_artists_lifecycle/},
      tracks_shadows        => {qw/foreign.rel_shadow_cds_lifecycle  self.shadowed_lifecycle/},
      single_track_shadows  => {qw/foreign.shadowed_lifecycle        self.rel_shadow_tracks_lifecycle/},
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
      older_shadows     => '_CUSTOM_',
      newer_shadows     => '_CUSTOM_',
      cd_shadows        => {qw/foreign.shadowed_lifecycle           self.rel_shadow_cds_lifecycle/},
      cd_single_shadows => {qw/foreign.rel_shadow_tracks_lifecycle  self.shadowed_lifecycle/},
    },
  },
  'All relationships correctly set',
);

$s->deploy();

# make everything happen in "steps", ++ing after each op
$s->{_shadow_changeset_timestamp} = '666';

note('add artist + painting + 2 cds + 3 tracks each, try literal non-pks');
my $a_gaga = $s->resultset('Artist')->create({
  name => 'gaga',
  paintings => [{ title => 'killed_this_way'}],
  cds => [
    { title => 'stab', tracks => [
      { title => 'rusty_spoon' },
      { title => 'lethal_umbrella' },
      { title => \ '"crappy_plunger"' },
    ]},
    { title => 'twist', tracks => [
      { title => 'phillips' },
      { title => 'flathead' },
      { title => 'star_of_david' },
    ]},
  ]
});
$s->{_shadow_changeset_timestamp}++;

note('rename artist');
$a_gaga->update({ name => 'the_laaaadyyyy' });
$s->{_shadow_changeset_timestamp}++;

note('retitle one track (trying scalarref again)');
my $t_plunger = $s->resultset('Track')->find({ title => 'crappy_plunger' });
$t_plunger->update({ title => \ '"sparkly_plunger"' });
$s->{_shadow_changeset_timestamp}++;

note('add a single based on the retitled track');
$t_plunger->create_related(cd_single => {
  title => 'unplugged',
  artist => $a_gaga,
  tracks => [
    { title => 'unclogging_action' },
    { title => 'hardcore_suction' },
  ],
});
$s->{_shadow_changeset_timestamp}++;

note('add an extra artist with a cd with 2 tracks, with a single on 2nd track, with one track itself');
my $a_pink = $s->resultset('Artist')->create({
  name => 'pink',
  paintings => [ { title => 'pink-ponk' } ],
  cds => [{
    title => 'still_a_"rockstar"',
    tracks => [
      { title => 'more_a_*ockstar' },
      { title => 'dear_mr_president',
        cd_single => {
          title => "barry_o'bama",
          artist => { name => 'pink' },
          tracks => [{ title => 'mr_44' }],
        }
      },
    ],
  }],
});
$s->{_shadow_changeset_timestamp}++;

note("move each cd's first track to the end");
for ($s->resultset('Track')->search({ position => 1 })) {
  $_->move_last;
  $s->{_shadow_changeset_timestamp}++ if $_->position > 1;
}

note('delete the 1st track off each cd of the 1st artist');
$a_gaga->cds->search_related('tracks', { position => 1 })->delete_all;
$s->{_shadow_changeset_timestamp}++;

note('add aliases to artists');
my $i = 1;
for ($s->resultset('Artist')->all) {
  $_->update({ alias => 'Number_' . $i++ });
  $s->{_shadow_changeset_timestamp}++;
}

note('add a 3rd artist');
my $a_snatch = $s->resultset('Artist')->create({ name => 'sneaky' });
$s->{_shadow_changeset_timestamp}++;

note('re-link both singles to the new artist');
$s->resultset('CD')->search({ single_track_cdid => { '!=', undef } })->update_all({ artist => $a_snatch });
$s->{_shadow_changeset_timestamp}++;

note('change the 3rd artist name');
$a_snatch->update({ name => 'very_sneaky', alias => 'SNEAK-er' });
$s->{_shadow_changeset_timestamp}++;

note('retitle all cds');
$_->update({ title => $_->title . '(tm)' }) for $s->resultset('CD')->all;
$s->{_shadow_changeset_timestamp}++;

note('delete the other 2 artists');
$s->resultset('Artist')->search({ name => { '!=', 'very_sneaky' }})->delete_all;
$s->{_shadow_changeset_timestamp}++;

#use Data::Dumper::Concise;
#die Dumper
my $s_state = { map {
  my @cols = $s->source($_)->columns;
  $_ => [ \@cols, map
    {[ map { defined $_ ? $_ . '' : '_UNDEF_' } @$_ ]}
    $s->resultset($_)->search({}, { columns => \@cols, order_by => [$s->source($_)->primary_columns] })->cursor->all
  ]
} $s->sources };

# briefly on how this works:
# * every time a shadowed row is created, a new "shadowed_lifecycle" is established, and the tracked
# values are recorded in the corresponding shadow
# * every time any update takes place a new shadow is created to reflect changes
# * once a row is deleted, all its existing shadows have their pk-pointing-fks set to NULL
# * lifecycle is an integer that increments once per INSERT and stays the sime for the
# lifetime of the shadowed row. This is what we use to build relationships between shadows
#use Test::Differences;
#eq_or_diff(
is_deeply(
  $s_state,
  {
    Painting => [ # never tracked - nothing left
      [qw/  id    artist_name   title /],
    ],
    Artist => [
      [qw/  name          alias       /],
      [qw/  very_sneaky   SNEAK-er    /],
    ],
    'Artist::Shadow' => [
      [qw/  shadow_id shadow_timestamp  shadow_stage  shadowed_lifecycle  shadowed_curpk_name shadow_val_name shadow_val_alias  /],
      [qw/  1         666               2             1                   _UNDEF_             gaga            _UNDEF_           /],
      [qw/  2         667               1             1                   _UNDEF_             the_laaaadyyyy  _UNDEF_           /],
      [qw/  3         670               2             2                   _UNDEF_             pink            _UNDEF_           /],
      [qw/  4         676               1             1                   _UNDEF_             the_laaaadyyyy  Number_1          /],
      [qw/  5         677               1             2                   _UNDEF_             pink            Number_2          /],
      [qw/  6         678               2             3                   very_sneaky         sneaky          _UNDEF_           /],
      [qw/  7         680               1             3                   very_sneaky         very_sneaky     SNEAK-er          /],
      [qw/  8         682               0             1                   _UNDEF_             the_laaaadyyyy  Number_1          /],
      [qw/  9         682               0             2                   _UNDEF_             pink            Number_2          /],
    ],
    CD => [
      [qw/  id  artist_name   title             single_track_cdid single_track_pos    /],
      [qw/  3   very_sneaky   unplugged(tm)     _UNDEF_           _UNDEF_             /],
      [qw/  5   very_sneaky   barry_o'bama(tm)  _UNDEF_           _UNDEF_             /],
    ],
    'CD::Shadow' => [
      [qw/  shadow_id shadow_timestamp  shadow_stage  shadowed_lifecycle  shadowed_curpk_id shadow_val_title        rel_shadow_artists_lifecycle  rel_shadow_tracks_lifecycle /],
      [qw/  1         666               2             1                   _UNDEF_           twist                   1                             _UNDEF_                     /],
      [qw/  2         666               2             2                   _UNDEF_           stab                    1                             _UNDEF_                     /],
      [qw/  3         669               2             3                   3                 unplugged               1                             4                           /],
      [qw/  4         670               2             4                   _UNDEF_           still_a_"rockstar"      2                             _UNDEF_                     /],
      [qw/  5         670               2             5                   5                 barry_o'bama            2                             9                           /],
      [qw/  6         679               1             3                   3                 unplugged               3                             4                           /],
      [qw/  7         679               1             5                   5                 barry_o'bama            3                             9                           /],
      [qw/  8         681               1             2                   _UNDEF_           stab(tm)                1                             _UNDEF_                     /],
      [qw/  9         681               1             1                   _UNDEF_           twist(tm)               1                             _UNDEF_                     /],
      [qw/  10        681               1             3                   3                 unplugged(tm)           3                             4                           /],
      [qw/  11        681               1             4                   _UNDEF_           still_a_"rockstar"(tm)  2                             _UNDEF_                     /],
      [qw/  12        681               1             5                   5                 barry_o'bama(tm)        3                             9                           /],
      [qw/  13        682               0             2                   _UNDEF_           stab(tm)                1                             _UNDEF_                     /],
      [qw/  14        682               0             1                   _UNDEF_           twist(tm)               1                             _UNDEF_                     /],
      [qw/  15        682               0             4                   _UNDEF_           still_a_"rockstar"(tm)  2                             _UNDEF_                     /],
    ],
    Track => [
      [qw/  cd_id title             position  /],
      [qw/  3     unclogging_action 1         /],
      [qw/  5     mr_44             1         /],
    ],
    'Track::Shadow' => [
      [qw/  shadow_id shadow_timestamp  shadow_stage  shadowed_lifecycle  shadowed_curpk_cd_id  shadowed_curpk_position shadow_val_title  shadow_val_position rel_shadow_cds_lifecycle/],
      [qw/  1         666               2             1                   _UNDEF_               _UNDEF_                 star_of_david     3                   1                       /],
      [qw/  2         666               2             2                   _UNDEF_               _UNDEF_                 flathead          2                   1                       /],
      [qw/  3         666               2             3                   _UNDEF_               _UNDEF_                 phillips          1                   1                       /],
      [qw/  4         666               2             4                   _UNDEF_               _UNDEF_                 crappy_plunger    3                   2                       /],
      [qw/  5         666               2             5                   _UNDEF_               _UNDEF_                 lethal_umbrella   2                   2                       /],
      [qw/  6         666               2             6                   _UNDEF_               _UNDEF_                 rusty_spoon       1                   2                       /],
      [qw/  7         668               1             4                   _UNDEF_               _UNDEF_                 sparkly_plunger   3                   2                       /],
      [qw/  8         669               2             7                   _UNDEF_               _UNDEF_                 hardcore_suction  2                   3                       /],
      [qw/  9         669               2             8                   3                     1                       unclogging_action 1                   3                       /],
      [qw/  10        670               2             9                   _UNDEF_               _UNDEF_                 dear_mr_president 2                   4                       /],
      [qw/  11        670               2             10                  5                     1                       mr_44             1                   5                       /],
      [qw/  12        670               2             11                  _UNDEF_               _UNDEF_                 more_a_*ockstar   1                   4                       /],
      [qw/  13        671               1             6                   _UNDEF_               _UNDEF_                 rusty_spoon       0                   2                       /],
      [qw/  14        671               1             5                   _UNDEF_               _UNDEF_                 lethal_umbrella   1                   2                       /],
      [qw/  15        671               1             4                   _UNDEF_               _UNDEF_                 sparkly_plunger   2                   2                       /],
      [qw/  16        671               1             6                   _UNDEF_               _UNDEF_                 rusty_spoon       3                   2                       /],
      [qw/  17        672               1             3                   _UNDEF_               _UNDEF_                 phillips          0                   1                       /],
      [qw/  18        672               1             2                   _UNDEF_               _UNDEF_                 flathead          1                   1                       /],
      [qw/  19        672               1             1                   _UNDEF_               _UNDEF_                 star_of_david     2                   1                       /],
      [qw/  20        672               1             3                   _UNDEF_               _UNDEF_                 phillips          3                   1                       /],
      [qw/  21        673               1             8                   3                     1                       unclogging_action 0                   3                       /],
      [qw/  22        673               1             7                   _UNDEF_               _UNDEF_                 hardcore_suction  1                   3                       /],
      [qw/  23        673               1             8                   3                     1                       unclogging_action 2                   3                       /],
      [qw/  24        674               1             11                  _UNDEF_               _UNDEF_                 more_a_*ockstar   0                   4                       /],
      [qw/  25        674               1             9                   _UNDEF_               _UNDEF_                 dear_mr_president 1                   4                       /],
      [qw/  26        674               1             11                  _UNDEF_               _UNDEF_                 more_a_*ockstar   2                   4                       /],
      [qw/  27        675               1             5                   _UNDEF_               _UNDEF_                 lethal_umbrella   0                   2                       /],
      [qw/  28        675               1             4                   _UNDEF_               _UNDEF_                 sparkly_plunger   1                   2                       /],
      [qw/  29        675               1             6                   _UNDEF_               _UNDEF_                 rusty_spoon       2                   2                       /],
      [qw/  30        675               1             5                   _UNDEF_               _UNDEF_                 lethal_umbrella   3                   2                       /],
      [qw/  31        675               0             5                   _UNDEF_               _UNDEF_                 lethal_umbrella   3                   2                       /],
      [qw/  32        675               1             2                   _UNDEF_               _UNDEF_                 flathead          0                   1                       /],
      [qw/  33        675               1             1                   _UNDEF_               _UNDEF_                 star_of_david     1                   1                       /],
      [qw/  34        675               1             3                   _UNDEF_               _UNDEF_                 phillips          2                   1                       /],
      [qw/  35        675               1             2                   _UNDEF_               _UNDEF_                 flathead          3                   1                       /],
      [qw/  36        675               0             2                   _UNDEF_               _UNDEF_                 flathead          3                   1                       /],
      [qw/  37        675               1             7                   _UNDEF_               _UNDEF_                 hardcore_suction  0                   3                       /],
      [qw/  38        675               1             8                   3                     1                       unclogging_action 1                   3                       /],
      [qw/  39        675               1             7                   _UNDEF_               _UNDEF_                 hardcore_suction  2                   3                       /],
      [qw/  40        675               0             7                   _UNDEF_               _UNDEF_                 hardcore_suction  2                   3                       /],
      [qw/  41        682               0             6                   _UNDEF_               _UNDEF_                 rusty_spoon       2                   2                       /],
      [qw/  42        682               0             4                   _UNDEF_               _UNDEF_                 sparkly_plunger   1                   2                       /],
      [qw/  43        682               0             3                   _UNDEF_               _UNDEF_                 phillips          2                   1                       /],
      [qw/  44        682               0             1                   _UNDEF_               _UNDEF_                 star_of_david     1                   1                       /],
      [qw/  45        682               0             11                  _UNDEF_               _UNDEF_                 more_a_*ockstar   2                   4                       /],
      [qw/  46        682               0             9                   _UNDEF_               _UNDEF_                 dear_mr_president 1                   4                       /],
    ]
  },
  'Schema state as expected after manipulations',
);

done_testing;
