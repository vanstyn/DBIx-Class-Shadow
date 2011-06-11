package DBIx::Class::Shadow::ResultSet;

use warnings;
use strict;

use base qw/DBIx::Class::ResultSet/;

sub last_shadow_rs {
  shift->search_rs({ 'newer_shadows.shadow_id' => undef }, { join => 'newer_shadows' });
}

sub version {
  $_[0]->search(undef, {
    order_by => 'shadow_id',
  })->slice($_[1] - 1)
}

sub after {
  $_[0]->search(undef, {
    order_by => 'shadow_id',
    offset   => $_[1],
  })
}

sub before {
  my $self = shift;

  my $version_query =
    $self->version($_[0])->get_column('shadow_id')->as_query;

  $self->search({
     shadow_id => { '<' => $version_query },
   }, {
     order_by => { -desc => 'shadow_id' },
   })
}

sub changeset {
  my ($self, $changeset_id) = @_;

  $self->search({ changeset_id => { '<=' => $changeset_id }})
       ->as_subselect_rs
       ->search_related(next_shadows => { 'next_shadows.id' => undef })
}

1;
