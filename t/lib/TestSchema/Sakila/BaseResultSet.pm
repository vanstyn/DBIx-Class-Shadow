package TestSchema::Sakila::BaseResultSet;

use base qw/DBIx::Class::ResultSet/;

# FIXME: this is needed to prevent $rs changes from getting missed,
# which is a core API issue and shouldn't need to be done like this

sub update { shift->update_all(@_) };

sub delete { shift->delete_all(@_) };

sub populate {
  if (defined wantarray) {
    return shift->next::method(@_)
  }
  else {
    # Force out of void context to avoid Storage::insert_bulk
    my $res = shift->next::method(@_);
    return;
  }
}

1;

