package DBIx::Class::Schema::Shadow;

use warnings;
use strict;

use base qw/DBIx::Class::Schema/;

use Try::Tiny;

use List::Util qw/first/;
use List::UtilsBy qw/sort_by/;
use Time::HiRes qw/gettimeofday/;
use Storable qw/dclone/;
use Sub::Name qw/subname/;

use namespace::clean;

__PACKAGE__->mk_group_accessors (component_class => qw/
  shadow_result_base_class
  shadow_resultset_base_class
/);
__PACKAGE__->mk_group_accessors (inherited => qw/
  shadow_timestamp_datatype
  _shadow_changeset_resultclass
  _shadow_changeset_resultclass_valid
  _shadow_moniker_mappings
/);
__PACKAGE__->_shadow_moniker_mappings({});

sub clone {
  my $old_mappings = $_[0]->_shadow_moniker_mappings;
  my $self = shift->next::method(@_);
  $self->{_shadow_moniker_mappings} = dclone $old_mappings;
  $self;
}

# a user may want to change this if shadow_timestamp() is overriden
__PACKAGE__->shadow_timestamp_datatype('bigint');

__PACKAGE__->shadow_result_base_class('DBIx::Class::Shadow::Result');
__PACKAGE__->shadow_resultset_base_class('DBIx::Class::Shadow::ResultSet');

my $shadow_suffix = '::Shadow';
my $phantom_suffix = '::Phantom';
my $row_shadows_relname = 'shadows';
my $shadow_result_component = 'DBIx::Class::Shadow';

sub shadow_timestamp {
  # Use a combined value of epoch and zero-padded sub-second
  # time in units of *0.1 millisecond*.
  # The reason for this  is that a perl compiled with 32bit
  # ints (most 32bit machines, check $Config{ivsize} < 8) can
  # not handle more than 15 decimal digit numbers without
  # losing a significant amount of precision (this is a side
  # effect of perl using doubles to do most numeric ops, which
  # gives a rough limit of +- 2^52 on most current hardware).
  # In particular this affects DBI since most DBD drivers
  # transport numerics as numbers, not as strings, hence even
  # if we manage to write the right thing to the database, we
  # are not guaranteed to be able to read it out correctly.
  # Given how epoch will stay in the range of 10 digits
  # (2^31 - 1) for a while, we add extra 4 digits to stay far
  # from the limits imposed by perl
  # (also I dare anyone to insert at close to 10,000qps
  # even with massive parallelism and clustering)
  my @t = gettimeofday();
  return sprintf ("%d%04d", $t[0], int($t[1]/100) );
}

sub changeset_do {
  my $self = shift;
  my ($args, $code) = ref $_[0] eq 'CODE' ? ( {}, shift ) : (shift, shift );

  $self->throw_exception ('Expecting coderef as first (or second) argument')
    unless ref $code eq 'CODE';

  my $cset_class = $self->shadow_changeset_resultclass
    or $self->throw_exception(
      'changeset_do() can not be used without setting a shadow_changeset_resultclass'
    );

  my $cset_rsrc = $self->source($cset_class)
    or $self->throw_exception(
      "Resultclass $cset_class does not seem to be registered with this schema"
    );

  my $parent_cset = $self->{_shadow_changeset_rowobj};

  local $self->{_shadow_changeset_rowobj};

  $self->txn_do (sub {
    local $self->{_shadow_changeset_timestamp} = $self->shadow_timestamp
      unless $self->{_shadow_changeset_timestamp};

    $args->{timestamp} ||= $self->{_shadow_changeset_timestamp};
    $args->{parent_changeset} = $parent_cset if $parent_cset;

    my $cset = $self->{_shadow_changeset_rowobj} = $cset_class->new_changeset($cset_rsrc, $args);

    $cset->insert;

    $code->();
  });
}

sub shadow_changeset_resultclass {
  my $self = shift;
  if (@_) {
    $self->_shadow_changeset_resultclass_valid(undef);
    return $self->_shadow_changeset_resultclass(@_);
  }

  if (
    ! $self->_shadow_changeset_resultclass_valid
      and
    my $c = $self->_shadow_changeset_resultclass
  ) {
    $self->ensure_class_loaded($c);

    $self->throw_exception("Changeset class $c does not look like a Result class")
      unless $c->isa('DBIx::Class::Row');

    $self->throw_exception("Changeset class $c does not implement a new_changeset method")
      unless $c->can('new_changeset');

    my @pk = $c->primary_columns;
    $self->throw_exception("Changeset resultclass $c does not have a primary key column 'id'")
      unless (
        $c->has_column('id')
          and
        @pk == 1
          and
        $pk[0] eq 'id'
      );

    $self->throw_exception("Changeset resultclass $c must have an integer (INT) primary key column")
      unless $c->column_info('id')->{data_type} =~ /^ int(?:eger)? $/ix;

    $self->_shadow_changeset_resultclass_valid(1);
  }

  return $self->_shadow_changeset_resultclass;
}

sub register_class {
  my ($self, $moniker, $res_class) = @_;

  if ($res_class->isa ($shadow_result_component) ) {

    my ($shadow_class, $phantom_class) = $self->_gen_shadow_sources($res_class);

    my $shadow_rels;
    my $requested_relationships = $res_class->shadow_relationships;

    # in essence skip any relationship we can not yet work with *unless*
    # it was specifically requested
    for my $rel (@{ $requested_relationships || [ sort $res_class->relationships ] }) {
      next if $rel eq $row_shadows_relname;

      $self->throw_exception("Relationship clash - 'current_version' is a generated relationship for every shadow")
        if $rel eq 'current_version';

      try {
        $self->_gen_shadow_relationship($res_class, $rel)
      } catch {
        $self->throw_exception($_) if $requested_relationships;
        #warn "$_";
      };
    }

    # see if we need to link a changeset
    # we do it here, because we do not have access to $moniker earlier
    if (my $cset_class = $self->shadow_changeset_resultclass) {
      $shadow_class->belongs_to(changeset => $cset_class, 'shadow_changeset_id', {
        join_type => 'left', on_delete => 'restrict', on_update => 'cascade'
      });

      my $cset_sh_relname = lc $moniker;
      $cset_sh_relname =~ s/:+/_/g;
      $cset_sh_relname .= '_shadows';
      $cset_class->has_many( $cset_sh_relname => $shadow_class, 'shadow_changeset_id');
      $self->_reapply_source_prototype($cset_class);
    }

    # register the original source itself to resolve the resultset class
    $self->next::method ($moniker, $res_class);

    my $rs_class = $self->source($moniker)->resultset_class;
    my $phantom_rs_class = $rs_class . $phantom_suffix;
    require DBIx::Class::Shadow::Phantom::ResultSet;
    $self->inject_base($phantom_rs_class, 'DBIx::Class::Shadow::Phantom::ResultSet', $rs_class);

    $phantom_class->resultset_class($phantom_rs_class);

    # register extras and record moniker maps
    my $sh_moniker = $moniker . $shadow_suffix;
    $self->register_source($sh_moniker, $shadow_class->result_source_instance);
    my $ph_moniker = $moniker . $phantom_suffix;
    $self->register_source($ph_moniker, $phantom_class->result_source_instance);

    @{$self->_shadow_moniker_mappings->{shadows}||={}}{$moniker, $ph_moniker} = ($sh_moniker) x 2;
    @{$self->_shadow_moniker_mappings->{phantoms}||={}}{$moniker, $sh_moniker} = ($ph_moniker) x 2;
    @{$self->_shadow_moniker_mappings->{originals}||={}}{$ph_moniker, $sh_moniker} = ($moniker) x 2;
  }
  else {
    $self->next::method ($moniker, $res_class);
  }
}

sub _hash_for_rel { +{ map
  {( "foreign.$_" => "self.$_[1]->{$_}" )}
  keys %{$_[1]}
}}

sub _sort_colhash {
  my ($href, @cols) = $_[1];

  for (sort_by { $href->{$_}{__source_order} } keys %{$href||{}}) {
    push @cols, $_, { %{$href->{$_}} };
    delete $cols[-1]{__source_order};
  }

  @cols;
}

sub _gen_shadow_sources {
  my ($self, $res_class) = @_;

  my $shadow_class = $res_class . $shadow_suffix;
  my $phantom_class = $res_class . $phantom_suffix;

  # we may request the same shadow-generation repeatedly
  unless ($shadow_class->isa($self->shadow_result_base_class)) {

    my @pks = $res_class->primary_columns
      or $self->throw_exception('Unable to shadow sources without a primary key');

    my $res_table = $res_class->table;
    $self->throw_exception("Unable to shadow $res_class - non-scalar table names are not supported")
      if ref $res_table;

    # gen the shadow source/class
    $self->inject_base($shadow_class, $self->shadow_result_base_class);
    $shadow_class->table('shadow_' . $res_table);
    $shadow_class->resultset_class($self->shadow_resultset_base_class);

    my $columns_info = $res_class->columns_info;
    for (keys %$columns_info) {
      $columns_info->{$_} = {% {$columns_info->{$_}} };
      delete $columns_info->{$_}{is_auto_increment};
    }

    my $shadow_cols;
    for (@{$res_class->shadow_columns}) {
      my $inf = $columns_info->{$_} || $self->throw_exception (
        "Unable to shadow nonexistent column '$_' on $res_class"
      );
      $shadow_cols->{$_} = {
        %$inf,
        __source_order => scalar keys %$shadow_cols
      };
    }

    $shadow_class->add_columns(
      shadow_id => { data_type => 'INT', is_auto_increment => 1 },

      shadow_timestamp => { data_type => $self->shadow_timestamp_datatype },

      # 2 - insertion, 1 - update, 0 - deletion, -1 - internal update (rekey)
      shadow_stage => { data_type => 'TINYINT' },

      # always create this column, even if changesetting has not been requested
      # it most likely will be requested later on, and changing the shadow
      # schema just for this will blow
      shadow_changeset_id =>  { data_type => 'INT', is_nullable => 1 },

      shadowed_lifecycle => { data_type => 'INT', retrieve_on_insert => 1 },
      (map {( "shadowed_curpk_$_" => { %{$columns_info->{$_}}, is_nullable => 1 } )} @pks),
      $self->_sort_colhash( { map
        {( "shadow_val_$_" => { accessor => $_, %{$shadow_cols->{$_}} } )}
        keys %$shadow_cols
      }),
    );

    $shadow_class->set_primary_key('shadow_id');

    # gen the phantom source/class
    require DBIx::Class::Shadow::Phantom::Result;
    $self->inject_base($phantom_class, 'DBIx::Class::Shadow::Phantom::Result', $res_class);

    # get a source clone - *DELIBERATELY* share everything except for
    # the relationship definitions
    # down the road (when the main source is registsred and the resultset
    # class is fully resolved) - we will swap the default resultset class too
    my $orig_rsrc = $res_class->result_source_instance;
    my $ph_rsrc = bless {
      %$orig_rsrc,
      _relationships => {},
      result_class => $phantom_class,
      resultset_class => '_UNSET_'
    }, ref $orig_rsrc;
    delete $ph_rsrc->{schema}; # otherwise we leak it via classdata
    $phantom_class->table($ph_rsrc);

    # deal with row-to-shadow relationships (inter-shadow/phantom rels come in later)
    # linkage to shadowed source
    my $current_belongs_to = { map {( $_ => "shadowed_curpk_$_" )} @pks };

    $shadow_class->belongs_to(current_version => $res_class, $self->_hash_for_rel($current_belongs_to), {
      on_delete => 'set null', on_update => 'cascade', join_type => 'left',
    });

    $shadow_class->has_many(older_shadows => $shadow_class, sub {(
      {
        "$_[0]->{foreign_alias}.shadowed_lifecycle" => { -ident => "$_[0]->{self_alias}.shadowed_lifecycle" },
        "$_[0]->{foreign_alias}.shadow_id" => { '<' => { -ident => "$_[0]->{self_alias}.shadow_id" } },
      },
      $_[0]->{self_rowobj} && {
        "$_[0]->{foreign_alias}.shadowed_lifecycle" => $_[0]->{self_rowobj}->shadowed_lifecycle,
        "$_[0]->{foreign_alias}.shadow_id" => { '<' => $_[0]->{self_rowobj}->shadow_id },
      },
    )}, { cascade_rekey => 0, cascade_delete => 0 } );

    $shadow_class->has_many(newer_shadows => $shadow_class, sub {(
      {
        "$_[0]->{foreign_alias}.shadowed_lifecycle" => { -ident => "$_[0]->{self_alias}.shadowed_lifecycle" },
        "$_[0]->{foreign_alias}.shadow_id" => { '>' => { -ident => "$_[0]->{self_alias}.shadow_id" } },
      },
      $_[0]->{self_rowobj} && {
        "$_[0]->{foreign_alias}.shadowed_lifecycle" => $_[0]->{self_rowobj}->shadowed_lifecycle,
        "$_[0]->{foreign_alias}.shadow_id" => { '>' => $_[0]->{self_rowobj}->shadow_id },
      },
    )}, { cascade_rekey => 0, cascade_delete => 0 } );

    # This is the change on the original $res_class, no reapply needed
    # as it has not been register_source()d yet
    $res_class->has_many($row_shadows_relname => $shadow_class, $self->_hash_for_rel({ reverse %$current_belongs_to}),
      { cascade_delete => 0 }, # FIXME - need to think what to do about cascade_copy - not clear-cut
    );

    # register default stubs for the phantom so that relationship
    # generated acessors are *NOT* navigable by default
    # we will overwrite these throw-stubs with the real deal for
    # shadowed relationships
    for my $relname (keys %{$orig_rsrc->{_relationships}}) {
      no strict 'refs';
      no warnings 'redefine';
      if ($orig_rsrc->{_relationships}{$relname}{attrs}{accessor}) {
        my $acc = "${phantom_class}::${relname}";
        *$acc = subname $acc => sub {
          shift->throw_exception("Unable to navigate non-shadowed relationship '$relname' from phantom object");
        };
      }
    }
  }

  return ($shadow_class, $phantom_class);
}

sub _gen_shadow_relationship {
  my ($self, $res_class, $rel) = @_;

  my $rsrc = $res_class->result_source_instance;

  my $relinfo = $rsrc->relationship_info ($rel)
    or $self->throw_exception("No such relationship '$rel' on $res_class");

  my $foreign_class = $relinfo->{class};

  $self->throw_exception("Unable to shadow requested relationship '$rel' pointing to a non-shadowed class $foreign_class")
    unless $foreign_class->isa($shadow_result_component);

  my $cond = $relinfo->{cond};

  # FIXME: it is quite possible to support more relationship types than what we
  # do here, but I have no need yet, and it is... hairy :)
  #
  # For now examine any relationship and as long as it is to/from a foreign/our PK
  # we just use the lifecycle (since each lifecycle points to a specific PK group)
  # Also note that *all* resulting relationships will be has_many's back in the
  # register_class caller, since even if CD belongs to a single artist, the artist
  # can very well have *multiple* versions (say a name change) all under the same
  # lifecycle. Use the timestamp to additionally correlate and limit the results.
  #
  # There is of course a complication - if there is a *foreign* shadow which needs
  # to hold an fk to *our* lifecycle, there is no way to ensure this shadow has
  # been in fact defined. So what we do is make sure that everything is define-able
  # on the fly. Each piece of this puzzle checks whether the previous steps of
  # defining the class, adding columns, etc have already been executed, hence the
  # relative safety of doing this as we go.

  $self->throw_exception(
    'Shadowing currently only supported for static hash-based relationship conditions, '
  . "unable to shadow '$rel' on $res_class to $foreign_class"
  ) if (ref $cond ne 'HASH');

  my $stripped_cond = { map {
    my ($fc) = $_ =~ /^foreign\.(.+)/
      or $self->throw_exception("Malformed condition foreign-part '$_' of '$rel' on $res_class");

    my ($sc) = $cond->{$_} =~ /^self\.(.+)/
      or $self->throw_exception("Malformed condition self-part '$cond->{$_}' of '$rel' on $res_class");

    ($fc => $sc);

  } keys %$cond };

  my ($our_shadow, $foreign_shadow) = map
    { ($self->_gen_shadow_sources($_))[0] }
    ($res_class, $foreign_class)
  ;

  my $shadow_rel_cond;
  if (! exists $relinfo->{attrs}{is_foreign}) {
    $self->throw_exception(
      "Unable to shadow relationship '$rel' - shadowing requires an explicitly specified 'is_foreign' flag"
    );
  }
  elsif ($relinfo->{attrs}{is_foreign}) {
    $self->throw_exception(
      "Unable to shadow relationship '$rel' on $res_class to $foreign_class - "
     .'only relationships containing the entire foreign PK are currently supported'
    ) if first { ! exists $stripped_cond->{$_} } $foreign_class->primary_columns;

    # simple foreign lifecycle-based relation - add the foreign col if necessary and declare the rel
    my $foreign_id_col = 'rel_' . $foreign_shadow->table . '_lifecycle';
    my $optional_belongs_to = ($relinfo->{attrs}{join_type}||'') =~ /^left/i;

    unless ($our_shadow->has_column ($foreign_id_col)) {
      $our_shadow->add_column(
        $foreign_id_col => {
          data_type => 'INT',
          retrieve_on_insert => 1,
          is_nullable => $optional_belongs_to ? 1 : 0
        },
      );
      $self->_reapply_source_prototype($our_shadow);
    }

    $shadow_rel_cond = { 'foreign.shadowed_lifecycle' => "self.${foreign_id_col}" };

    # ensure that we always know whether or the belongs_to is actually there
    if ($optional_belongs_to) {
      for (values %$stripped_cond) {
        $rsrc->add_columns( ('+' . $_) => { retrieve_on_insert => 1 } );
      }
    }
  }
  else {
    my $rev_cond = { reverse %$stripped_cond };
    $self->throw_exception(
      "Unable to shadow relationship '$rel' on $res_class to $foreign_class - "
     .'only relationships containing the entire local PK are currently supported'
    ) if first { ! exists $rev_cond->{$_} } $res_class->primary_columns;

    # simple local lifecycle-based relation - add the foreign col to the other side if necessary and declare the rel
    my $our_id_fk_col = 'rel_' . $our_shadow->table . '_lifecycle';

    unless ($foreign_shadow->has_column ($our_id_fk_col)) {
      $foreign_shadow->add_column(
        $our_id_fk_col => { data_type => 'INT', retrieve_on_insert => 1 }
      );
      $self->_reapply_source_prototype($foreign_shadow);
    }

    $shadow_rel_cond = { "foreign.${our_id_fk_col}" => 'self.shadowed_lifecycle' };
  }

####
# This is where I need to add relationships to the phantom class, except they
# can not be has_many's - they need to be regular encapsulates of "last shadow"
# this *is* currently possible, it just gets very very hairy, hence thinking how
# to do it right...
###

  # do not deploy any FK constraints
  my $sh_relname = "${rel}_shadows";
  $our_shadow->has_many($sh_relname => $foreign_shadow, $shadow_rel_cond, {
    shadows_original_relname => $rel,
    cascade_rekey => 1,

    # inherit this so we have a sense of direction
    is_foreign => $relinfo->{attrs}{is_foreign},

    # FIXME - perhaps need to inherit this too, not sure if will result in
    # deployable stuff however (it's a has_many <-> has_many)
    is_foreign_key_constraint => 0,
  });

  $relinfo->{attrs}{shadowed_by_relname} = $sh_relname;
  $self->_reapply_source_prototype($rsrc);
}

# when some changes are made to a source we want to find its
# instances and re-register them, so that the prototype changes
# get applied to the registered instances
# This does not cause inf-loops, since we overload regislter_class,
# not register_source
# However it *may* fuck up something else that hooks register_source
# as it effectively will re-execute quite a lot
sub _reapply_source_prototype {
  my ($self, $modified_source) = @_;

  my $result_class = ref $modified_source
    ? $modified_source->result_class
    : $modified_source
  ;

  for my $moniker ($self->sources) {
    if ($self->class($moniker) eq $result_class) {
      $self->unregister_source($moniker);
      $self->register_source($moniker, ref $modified_source ? $modified_source : $result_class->result_source_instance);
    }
  }
}

# like ->sources() but limited to shadows:
sub shadow_sources {
  my $self = shift;
  my %s = map {$_=>1} values %{$self->_shadow_moniker_mappings->{shadows}};
  return keys %s;
}

# like ->sources() but limited to originals (i.e. not shadows/phantoms):
sub shadowed_sources {
  my $self = shift;
  my %s = map {$_=>1} values %{$self->_shadow_moniker_mappings->{originals}};
  return keys %s;
}

# deploy only shadow sources
sub deploy_shadows {
  my ($self, $sqltargs, @args) = @_;
  $sqltargs ||= {};
  $sqltargs->{sources} = [$self->shadow_sources];
  return $self->deploy($sqltargs, @args);
}

# Initialize shadows for *all* rows in shadowed sources. This is
# only intended for turning on shadowing for a database with existing
# data. WARNING: this could be **very** heavy, depending on number
# of rows
sub init_all_row_shadows {
  my $self = shift;

  my $guard = $self->txn_scope_guard
    unless $self->{_shadow_changeset_rows};

  local $self->{_shadow_changeset_rows} = []
    if $guard;

  for my $rsrc (map {$self->source($_)} $self->shadowed_sources) {
    for my $Row ($rsrc->resultset->all) {
      next if ($Row->shadows->count > 0);

      # TODO: use a custom stage instead of '2' (insert) to distinguish?
      push @{$self->{_shadow_changeset_rows}}, $Row->_instantiate_shadow_row(2);
    }
  }

  if ($guard) {
    # FIXME: are there any stack/order considerations to worry about here? 
    #  don't think so since we're looking at *existing* rows...
    $_->insert for @{$self->{_shadow_changeset_rows}};
    $guard->commit;
  }

  1;
}

# Deploy shadow sources and initialize shadows for existing rows at once
sub deploy_init_shadows {
  my $self = shift;
  $self->deploy_shadows(@_);
  $self->init_all_row_shadows;
}

1;

=head1 NAME

DBIx::Class::Schema::Shadow

=head1 METHODS

=head2 changeset_do

 $schema->changeset_do(sub {
   ...
 });

=head2 shadow_result_base_class

 __PACKAGE__->shadow_result_base_class('MyApp::Schema::Shadow::Result');

C<shadow_result_base_class> sets the base class for the generated shadow
results.

# FIXME: Are there requirements for the base class?

=head2 shadow_resultset_base_class

 __PACKAGE__->shadow_resultset_base_class('MyApp::Schema::Shadow::ResultSet');

C<shadow_resultset_base_class> sets the base class for the generated shadow
resultsets.  Note that you should (but are not required to) base your custom
resultset base on the default resultset, which is
L<DBIx::Class::Shadow::ResultSet>.

=head2 shadow_changeset_resultclass

 __PACKAGE__->shadow_changeset_resultclass('MyApp::Schema::Result::Changeset');

C<shadow_changeset_resultclass> is the class that stores information related to
changesets.  By default this is merely a timestamp, but other obvious things to
store would be a user_id and a session_id.  Note that the class must be a
C<DBIx::Class::Row>, must have an C<id> column of type C<int>, and must provide
a C<new_changeset> method, which will be passed a hashref containing
an integer for C<timestamp>, an object for C<parent_changeset>, and any other
parameters that were passed to L</changeset_do>.

=head2 shadow_timestamp

You will probably never call this method, but what you may do instead is
override it.  See, some databases, like SQLite and MySQL don't have subsecond
precision in their DateTime columns, which is a huge problem for database
auditing, so we just use a high precision unix time int to handle that.  But
if you use a higher quality database that does have subsecond precision, you
may want to consider making shadow_timestamp a real datetime.

=head2 shadow_timestamp_datatype

 __PACKAGE__->shadow_timestamp_datatype('DateTime')

See L</shadow_timestamp> and make sure you set this appropriately.

=cut
