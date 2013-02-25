package DBICTest::S::BaseResultSet;

use base qw/DBIx::Class::ResultSet/;

sub update { shift->update_all(@_) };

sub delete { shift->delete_all(@_) };

sub populate {
  if (defined wantarray) {
    return shift->populate(@_)
  }
  else {
    # Force out of void context to avoid Storage::insert_bulk
    my $res = shift->populate(@_);
    return;
  }
}

1;

