package DBIx::Class::Shadow::ResultSet;

use warnings;
use strict;

use base qw/DBIx::Class::ResultSet/;

use Scalar::Util 'blessed';
use Sub::Name;

sub last_shadow_rs {
  shift->search_rs({ 'newer_shadows.shadow_id' => undef }, { join => 'newer_shadows' });
}

sub version {
  $_[0]->search(undef, {
    order_by => 'shadow_id',
  })->slice($_[1] - 1)
}

my $super_epoch = sub {
   my $ns = $_[0]->nanosecond;
   $ns =~ s/^(\d\d\d).*/$1/;
   $_[0]->epoch . $ns
};

sub after_version {
  $_[0]->search(undef, {
    order_by => 'shadow_id',
    offset   => $_[1],
  })
}

# FIXME: how are we going to handle people using a different type here?
sub after_datetime {
  my ($self, $dt) = @_;

  $self->throw_exception('after datetime requires a datetime object!')
    unless blessed($dt) && $dt->isa('DateTime');

  $self->search({
    shadow_timestamp => { '>' => $dt->$super_epoch },
  }, {
    order_by => 'shadow_id',
  })
}

sub before_version {
  my $self = shift;

  my $version_query =
    $self->version($_[0])->get_column('shadow_id')->as_query;

  $self->search({
     shadow_id => { '<' => $version_query },
   }, {
     order_by => { -desc => 'shadow_id' },
   })
}

sub before_datetime {
  my ($self, $dt) = @_;

  $self->throw_exception('before datetime requires a datetime object!')
    unless blessed($dt) && $dt->isa('DateTime');

  $self->search({
    shadow_timestamp => { '<' => $dt->$super_epoch },
  }, {
    order_by => 'shadow_id',
  })
}

{
   my %map = (
      version => 1,
      datetime => 1,
   );
   no strict 'refs';
   for my $meth (qw(before after)) {
      *{$meth} = subname $meth => sub {
         my ($self, $kind, $val) = @_;

         if (exists $map{$kind}) {
            my $m = "${meth}_$kind";
            return $self->$m($val);
         }
      }
   }
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
};

sub inserts { shift->$stage(2) }
sub updates { shift->$stage(1) }
sub deletes { shift->$stage(0) }

1;

=head1 NAME

DBIx::Class::Shadow::ResultSet

=head1 DESCRIPTION

This package is the (default) base class for all generated shadow classes'
ResultSet classes.  The methods defined are thus available when you access any
form of shadow resultset.

=head1 METHODS

=head2 last_shadow_rs

Returns a resultset containing the newest shadow

=head2 version

 $rs->version(4);

Returns a resultset containing the fourth shadow, where the first is the oldest

=head2 after

 $rs->after(
   version => 4,
 );

 $rs->after(
   datetime => $datetime_object,
 );

 $rs->after(
   changeset => $changeset_id,
 );

 $rs->after(
   changeset_datetime => $datetime,
 );

=head2 before

 $rs->before(
   version => 4,
 );

 $rs->before(
   datetime => $datetime_object,
 );

 $rs->before(
   changeset => $changeset_id,
 );

 $rs->before(
   changeset_datetime => $datetime,
 );

=head2 changeset

=head2 groknik

 $rs->groknik($column, $from, $to);

Returns the specific shadow when C<$column> changed from C<$from> to C<$to>.

=head2 inserts

Returns a resultset with just inserts

=head2 updates

Returns a resultset with just updates

=head2 deletes

Returns a resultset with just deletes
=cut
