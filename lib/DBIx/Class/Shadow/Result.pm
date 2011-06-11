package DBIx::Class::Shadow::Result;

use warnings;
use strict;

use base qw/DBIx::Class::Relationship::Cascade::Rekey DBIx::Class::Core/;

sub _non_shadowed_result_class {
   # herp derp what a dump impl
   $_[0]->result_source->relationship_info('current_version')->{class};
}

sub as_result {
   my $self = shift;
   my $class = $self->_non_shadowed_result_class;

   my %columns = $self->get_columns;

   return $class->new({
      map {
         $_ =~ m/^shadow_val_(.+)$/;
         my $key = $1;
         $key => $columns{$_}
      } grep /^shadow_val_/, keys %columns
   })
}

1;
