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

   return $class->new({ $self->_vanilla_columns })
}

sub _vanilla_columns {
   my %columns = $_[0]->get_columns;

   map {
      $_ =~ m/^shadow_val_(.+)$/;
      my $key = $1;
      $key => $columns{$_}
   } grep /^shadow_val_/, keys %columns
}

# I think this should be in a separate component, but I don't know the
# namespace, so I'm leaving it here for now

my @stages = (qw( delete update insert ));

sub as_diff {
   my $self = shift;

   my $stage  = $stages[$self->shadow_stage];
   my $before = undef;
   my $after  = undef;
   if ($stage eq 'delete') {
      $before = { $self->_vanilla_columns };
   } elsif ($stage eq 'insert') {
      $after  = { $self->_vanilla_columns };
   } else {
      $before = { $self->previous->_vanilla_columns };
      $after  = { $self->_vanilla_columns };
   }
   return ($stage => $before, $after)
}

sub previous {
   $_[0]->older_shadows->search(undef, {
      order_by => { -desc => 'shadow_id' },
      rows => 1,
   })->next
}

sub next {
   $_[0]->older_shadows->search(undef, {
      order_by => { -asc => 'shadow_id' },
      rows => 1,
   })->next
}

1;
