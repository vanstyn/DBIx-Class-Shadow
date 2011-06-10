package DBIx::Class::Shadow::ResultSet;

use warnings;
use strict;

use base qw/DBIx::Class::ResultSet/;

sub last_shadow_rs {
  shift->search_rs({ 'newer_shadows.shadow_id' => undef }, { join => 'newer_shadows' });
}

1;
