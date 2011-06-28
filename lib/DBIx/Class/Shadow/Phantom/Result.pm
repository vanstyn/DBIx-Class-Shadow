package DBIx::Class::Shadow::Phantom::Result;

use warnings;
use strict;

use base qw/DBIx::Class::Core/;

sub insert {
  shift->throw_exception('Phantom rows can not be reinserted back into storage');
}

sub update {
  shift->throw_exception('Phantom rows are not updateable');
}

sub delete {
  shift->throw_exception('Phantom rows can not be deleted');
}

1;
