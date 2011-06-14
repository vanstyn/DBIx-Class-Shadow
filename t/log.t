use warnings;
use strict;

use lib 't/lib';
use DBICTest::S;

my $s = DBICTest::S->connect('dbi:SQLite::memory:');

$s->deploy();

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

$a_gaga->update({ name => 'the_laaaadyyyy' });

my $t_plunger = $s->resultset('Track')->find({ title => 'crappy_plunger' });
$t_plunger->update({ title => \ '"sparkly_plunger"' });

$t_plunger->create_related(cd_single => {
  title => 'unplugged',
  artist => $a_gaga,
  tracks => [
    { title => 'unclogging_action' },
    { title => 'hardcore_suction' },
  ],
});

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

for ($s->resultset('Track')->search({ position => 1 })) {
  $_->move_last;
}

$a_gaga->cds->search_related('tracks', { position => 1 })->delete_all;

my $i = 1;
for ($s->resultset('Artist')->all) {
  $_->update({ alias => 'Number_' . $i++ });
}

my $a_snatch = $s->resultset('Artist')->create({ name => 'sneaky' });

$s->resultset('CD')->search({ single_track_cdid => { '!=', undef } })->update_all({ artist => $a_snatch });

$a_snatch->update({ name => 'very_sneaky', alias => 'SNEAK-er' });

$_->update({ title => $_->title . '(tm)' }) for $s->resultset('CD')->all;

$s->resultset('Artist')->search({ name => { '!=', 'very_sneaky' }})->delete_all;

my $ordered = sub { shift->search(undef, { order_by => 'shadow_timestamp' }) };
my $artists = $s->resultset('Artist::Shadow')->$ordered;
my $cds = $s->resultset('CD::Shadow')->$ordered;

use Data::Dumper::Concise;

my $collapse = sub {
   no warnings;
   my ($l, $r) = @_;

   my %t;

   for (keys %$l) {
      if ($l->{$_} eq $r->{$_}) {
         delete $l->{$_};
         delete $r->{$_};
      } else {
         $t{$_} = [$l->{$_}, $r->{$_}]
      }
   }

   return \%t;
};

use Term::ANSIColor;
use DateTime;

my @data;
my $logtool = sub {
   my ($rs, $item) = @_;

   while (my $d = $rs->next) {
      my $out = '';
      my ($action, $l, $r) = $d->as_diff;
      if ($action eq 'insert') {
         $out .= color 'green';
         $out .= " + Created $item: " . $d->as_result->render . "\n";
      } elsif ($action eq 'delete') {
         $out .= color 'red';
         $out .= " - Deleted $item: " . $d->as_result->render . "\n";
      } else {
         my $t = $collapse->($l, $r);
         $out .= color 'yellow';
         $out .= "   Updated $item: " . $d->as_result->render_delta($t) . "\n";
      }
      $out .= color 'reset';
      push @data, [ $d->shadow_timestamp, $out ];
   }
};

$logtool->($artists, 'artist');
$logtool->($cds, 'CD');
$logtool->($s->resultset('Track::Shadow'), 'track');

print join "\n", map "$_->[0]\n$_->[1]", sort { $a->[0] <=> $b->[0] } @data;
