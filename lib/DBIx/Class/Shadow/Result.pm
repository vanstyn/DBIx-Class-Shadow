package DBIx::Class::Shadow::Result;

use warnings;
use strict;

use base qw/DBIx::Class::Relationship::Cascade::Rekey DBIx::Class::Core/;

sub as_result {
   my $self = shift;
   my $rsrc = $self->result_source;
   my $moniker = $rsrc->source_name;
   my $schema = $rsrc->schema;

   my $ph = $schema->source(
      $schema->_shadow_moniker_mappings->{phantoms}{$moniker}
         ||
      $self->throw_exception("$moniker does not seem to know its phantom source moniker...")
   )->resultset->new ({
      $self->_vanilla_columns,
      -result_source => $schema->source(
         $schema->_shadow_moniker_mappings->{originals}{$moniker}
            ||
         $self->throw_exception("$moniker does not seem to know its original source moniker...")
      ),
   });

   $ph->{-from_shadow} = {
      id => $self->shadow_id,
      timestamp => $self->shadow_timestamp,
   };

   $ph;
}

# FIXME - bad name
sub _vanilla_columns {
   my %columns = $_[0]->get_columns;

   map {
      $_ =~ m/^shadow_val_(.+)$/;
      my $key = $1;
      $key => $columns{$_}
   } grep /^shadow_val_/, keys %columns
}

my @stages = (qw( rekey delete update insert  ));

sub as_diff {
   my $self = shift;

   my $stage  = $stages[$self->shadow_stage + 1];
   my $before = undef;
   my $after  = undef;
   if ($stage eq 'delete') {
      $before = { $self->_vanilla_columns };
   } elsif ($stage eq 'insert') {
      $after  = { $self->_vanilla_columns };
   } else {
      $before = { $self->previous_shadow->_vanilla_columns };
      $after  = { $self->_vanilla_columns };
   }
   return ($stage => $before, $after)
}

sub previous_shadow {
   $_[0]->older_shadows->search(undef, {
      order_by => { -desc => 'shadow_id' },
      rows => 1,
   })->next
}

sub next_shadow {
   $_[0]->newer_shadows->search(undef, {
      order_by => { -asc => 'shadow_id' },
      rows => 1,
   })->next
}

1;

=head1 NAME

DBIx::Class::Shadow::Result

=head1 SYNOPSIS

 my $artist = $schema->resultset('Artist')->find(1);
 my $shadow = $artist->shadows->first;
 my $artist_from_shadow = $shadow->as_result;

=head1 DESCRIPTION

This package is the (default) base class for all generated shadow classes.  The
methods defined are thus available when you access any form of shadow object.

=head1 METHODS

=head2 as_result

 $shadow->as_result

Returns the given C<shadow> but with it's values inflated into the row that the
shadow is based on, so that all the actual row methods are available, including
relationships at shadowtime.

=head2 as_diff

 my ($action, $from, $to) = $shadow->as_diff

returns a list of

 action - ('insert', 'update', or 'delete')
 from   - undef or a hashref representing state before action
 to     - undef or a hashref representing state after action

=head2 next

 $shadow->next

Returns the next newer shadow after this one

=head2 previous

 $shadow->previous

Returns the next older shadow before this one

=cut
