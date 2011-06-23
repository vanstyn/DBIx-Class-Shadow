package DBICTest::S::Result::Changeset;

use warnings;
use strict;

use base qw/DBICTest::S::BaseResult/;

__PACKAGE__->table('changeset');

__PACKAGE__->add_columns(
  id          => { data_type => 'int', is_auto_increment => 1 },
  timestamp   => { data_type => 'bigint' },
  user_id     => { data_type => 'int', default_value => 0 },
  session_id  => { data_type => 'int', default_value => 0 },

  # bad idea - do not do this, for test purposes only
  parent_changeset_id => { data_type => 'int', is_nullable => 1 },
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->belongs_to(parent_changeset => __PACKAGE__, 'parent_changeset_id', {
  join_type => 'left'
});

sub new_changeset {
   my ($class, $rsrc, $args) = @_;

   $rsrc->resultset->new_result($args);
}

1;
