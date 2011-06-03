package DBIx::Class::Shadow;

use warnings;
use strict;

use base qw/DBIx::Class::Relationship::Cascade::Rekey DBIx::Class::Core/;

__PACKAGE__->mk_group_accessors (inherited => qw/shadow_relationships shadow_columns/);

1;
