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

my $as = sub {
   my ($aq, $as) = @_;

   my ($sql, @bind) = @{$$aq};
   return \["$sql $as", @bind ];
};

# FIXME: wtf frew.
sub groknik {
  my ($self, $col, $from, $to) = @_;

  my $subq = $self->related_resultset('older_shadows')->search({
    'older_shadows.shadow_id' => { -ident => 'me.shadow_id' },
  }, {
    order_by => { -desc => 'older_shadows.shadow_id' },
    rows => 1,
  })->get_column("shadow_val_$col")->as_query;

  $self->search(undef, {
    '+columns' => {
      before => $as->($subq,'before'),
      current => $as->($self->get_column("shadow_val_$col")->as_query,'current' ),
    },
  })->search({
    before => $from,
    current => $to,
  })->as_subselect_rs
}

my $stage = sub {
   my $self  = shift;
   my $stage = shift;

   my $me   = $self->current_source_alias;

   $self->search({ "$me.shadow_stage" => $stage });
}

sub inserts { shift->$stage(2) }
sub updates { shift->$stage(1) }
sub deletes { shift->$stage(0) }

1;
