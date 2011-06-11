package DBICTest::S::Result::Config;

use warnings;
use strict;

use base qw/DBICTest::S::BaseResult/;
__PACKAGE__->load_components(qw/Shadow/);

__PACKAGE__->table('config');

__PACKAGE__->add_columns(
  id => { data_type => 'int', is_auto_increment => 1 },
  key => { data_type => 'varchar', size => 30 },
  value => { data_type => 'varchar', size => 30 },
);

__PACKAGE__->set_primary_key('id');
__PACKAGE__->add_unique_constraint(['key']);

1;

#__PACKAGE__->load_components(qw(Shadow::Rels Shadow::Delta));

# method as_delta { $self->delta_class->new($self->previous->get_inflated_columns, $self->get_inflated_columns) }

# add's a belongs_tos (or has_ones?) called 'next' and 'previous' pointing to the other versions for this result
#__PACKAGE__->define_next_rel;
#__PACKAGE__->define_previous_rel;

#Shadow::Rels

# add's a has_many called 'versions' pointing to the other versions for this result
# optional args:
# {
#    name => 'versions',
# }
#__PACKAGE__->define_versions_rel;
