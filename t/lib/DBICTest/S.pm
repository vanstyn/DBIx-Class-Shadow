package DBICTest::S;

use warnings;
use strict;

use base qw/DBIx::Class::Schema/;
__PACKAGE__->load_components(qw/Schema::Shadow/);

__PACKAGE__->shadow_result_base_class( 'DBICTest::S::BaseShadowResult' );

__PACKAGE__->load_namespaces;

1;
