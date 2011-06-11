package DBICTest::S::Result::Artist;

use warnings;
use strict;

use base qw/DBICTest::S::BaseResult/;
__PACKAGE__->load_components(qw/Shadow/);

__PACKAGE__->table('artists');

__PACKAGE__->add_columns(
  name => { data_type => 'varchar', size => 30 },
  alias => { data_type => 'varchar', is_nullable => 1 },
);

__PACKAGE__->set_primary_key('name');

__PACKAGE__->has_many(cds => 'DBICTest::S::Result::CD', {qw/foreign.artist_name self.name/});
__PACKAGE__->has_many(paintings => 'DBICTest::S::Result::Painting', {qw/foreign.artist_name self.name/});

sub render {
   my $self = shift;

   my $ret = $self->name;
   $ret .= (sprintf " (%s)", $self->alias) if defined $self->alias;

   $ret
}

1;
