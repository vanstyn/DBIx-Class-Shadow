package # Hide from PAUSE 
     TestUtil;

# VERSION
# ABSTRACT: Util functions for DBIx::Class::AuditAny

#*CORE::GLOBAL::die = sub { require Carp; Carp::confess };

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(
 latest_shadow ok_matches_latest_shadow
);

use Test::More;

# convenience func - gets the latest shadow row from an Rs of shadows:
sub latest_shadow($) {
  my $ShadowRs = shift;
  return $ShadowRs->search_rs(undef,
    { order_by => { -desc => 'shadow_id' } }
  )->first;
}


sub ok_matches_latest_shadow {
  my $Row = shift;
  my $test_name = shift || "Current Row ($Row) matches its most recent Shadow";
  ok(
    my $ShadowRow = latest_shadow $Row->shadows,
    " Get Shadow /for:[$test_name]"
  );
  is_deeply(
    { $ShadowRow->as_result->get_columns },
    { $Row->get_columns },
    $test_name
  ) if ($ShadowRow);
}

1;