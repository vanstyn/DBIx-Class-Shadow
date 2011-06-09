package DBIx::Class::Shadow::Row;

use warnings;
use strict;

use base qw/DBIx::Class::Relationship::Cascade::Rekey DBIx::Class::Core/;

use Test::Deep::NoTest qw/eq_deeply/;
use namespace::clean;

sub _prev_shadows_rs {
  my $self = shift;
  $self->result_source->resultset->search_rs({
    shadowed_lifecycle => $self->shadowed_lifecycle,
    shadow_id => { '<', $self->shadow_id },
  });
}

sub _prev_shadow {
  shift->_prev_shadows_rs->search_rs({}, {
    order_by => { -desc => 'shadow_id' }, rows => 1
  })->single;
}

# this is how we prevent duplications of updates (it happens
# rarely, but still could)
sub insert {
  my $self = shift->next::method(@_);

  if ($self->{_possibly_duplicate_shadow} and eq_deeply(
    {
      $self->_prev_shadow->get_columns,
      shadow_id => $self->shadow_id,
      shadow_timestamp => $self->shadow_timestamp,
      shadow_stage => $self->shadow_stage,
    },
    { $self->get_columns },
  )) {
    # DIRTY HACK to delete a row without telling anyone
    DBIx::Class::ResultSet::delete(
      $self->result_source->resultset->search_rs($self->ident_condition)
    );
    $self->in_storage(0);
  }

  $self;
}

1;
