package # hide from PAUSE
    DBIx::Class::Relationship::Cascade::Rekey;

# Module completely undocumented and not unit tested. I know it works
# however, as Shadow relies on everything happening below to work flawlessly.
# Needs cleanup and de-duplication (the update/delete overrides are *almost*
# identical, except for scattered update/delete references).

use strict;
use warnings;
use DBIx::Class::Carp;

sub _track_storage_value {
  my ($self, $col) = @_;
  return $self->next::method($col) || do {
    my $track = 0;

    my $rsrc = $self->result_source_instance;
    for my $rel ( $rsrc->relationships ) {
      my $relinfo = $rsrc->relationship_info($rel);
      next unless $relinfo->{attrs}{cascade_rekey};
      my ($cond) = $rsrc->_resolve_condition($relinfo->{cond}, $rel, $self, $rel);
      if ($cond->{$col}) {
        $track = 1;
        last;
      }
    }

    $track;
  };
}

sub update {
  my ($self, $upd, @rest) = @_;

  $self->set_inflated_columns($upd) if $upd;

  my $rsrc = $self->result_source;
  my $rels = { map { $_ => $rsrc->relationship_info($_) } $rsrc->relationships };

  my $update_actions = {};
  for my $rel (grep { $rels->{$_}{attrs}{cascade_rekey} } keys %$rels) {
    # copy the logic from the SQLT Parser, and if all else fails - default to 'restrict'
    # cache the result
    $update_actions->{$rel} = $rels->{$rel}{attrs}{_update_rekey_action} ||= do {
      my $action;
      my (undef, $rev_rel_info) = eval { %{$rsrc->reverse_relationship_info($rel)} };

      if (exists $rev_rel_info->{attrs}{on_update}) {
        $action = $rev_rel_info->{attrs}{on_update};
      }
      else {
        $action = 'cascade' if $rels->{$rel}{attrs}{cascade_copy};
      }

      $action = lc( $action||'' );
      $action =~ s/^\s+|\s+$//g;

      # default to restrict
      $action = 'restrict' unless ($action eq 'cascade' or $action eq 'set null' or $action eq 'no action');

      $action;
    };
  }

  delete $update_actions->{$_} for grep { $update_actions->{$_} eq 'no action' } keys %$update_actions;

  if (keys %$update_actions) {
    my $guard = $rsrc->schema->txn_scope_guard;

    # will be deleted by next::method
    my $storage_side_values = $self->{_column_data_in_storage} || {};

    # create a "clone" as if it was never updated, so we can chain properly
    # off of it
    # use a manual construct so that neither new() overrides nor FilterColumn
    # get in the way
    $self->get_columns; # this forces deflation of any inflated-only data present
    my $old_self = bless({
      _column_data => { %{$self->{_column_data} || {}}, %$storage_side_values },
      _in_storage => 1,
      _result_source => $rsrc,
    }, ref $self);

    # first update the row itself, to allow server-side cascades
    $self->next::method(undef, @rest);

    for my $rel (keys %$update_actions) {
      my ($old_cond, $old_is_crosstable, $new_cond, $new_is_crosstable) = map {
        $rsrc->_resolve_condition(
          $rels->{$rel}{cond}, $rel, $_, $rel
        );
      } ($old_self, $self);

      # if a join is necessary it will not work - the original row is no longer there
      # as we udpated it in next::method above
      $self->throw_exception(sprintf
        "Unable to rekey '%s' - only join-free condition relationships are supported",
        $rsrc->source_name . '/' . $rel,
      ) if ($old_is_crosstable || $new_is_crosstable);

      my $rel_src = $rsrc->related_source($rel);
      my $rel_result = $rel_src->result_class;
      my $rel_rs = $rel_src->resultset->search($old_cond, { columns => [
        grep { $rel_result->_track_storage_value($_) } $rel_src->columns
      ]});

      if ($update_actions->{$rel} eq 'restrict') {
        $self->throw_exception(sprintf
          "Update violated ON UPDATE RESTRICT constraint on relationship '%s'",
          $rsrc->source_name . '/' . $rel,
        ) if $rel_rs->count;
      }
      else {
        if ($update_actions->{$rel} eq 'set null') {
          $new_cond->{$_} = undef for keys %$new_cond
        }
        else {
          my $self_rs;
          for my $col (keys %$new_cond) {
            # if we got a literal we have no idea what it could be containing
            # (maybe a value, but maybe an expression based on some jointable)
            # replace with direct query
            # FIXME - perhaps need to update $self with the fetched value while we are here?
            if(
              ref $new_cond->{$col} eq 'SCALAR'
                or
              (ref $new_cond->{$col} eq 'REF' and ref ${$new_cond->{$col}} eq 'ARRAY')
            ) {
              $new_cond->{$col}
                = ($self_rs ||= $rsrc->resultset->search($self->ident_condition))
                    ->get_column($col)
                     ->as_query
              ;
            }
          }
        }

        $rel_rs->update_all($new_cond);
      }
    }

    $guard->commit;
  }
  else {
    $self->next::method(undef, @rest);
  }

  return $self;
}

sub delete {
  my ($self, @rest) = @_;

  my $rsrc = $self->result_source;
  my $rels = { map { $_ => $rsrc->relationship_info($_) } $rsrc->relationships };

  my $delete_actions = {};
  for my $rel (grep { $rels->{$_}{attrs}{cascade_rekey} } keys %$rels) {
    # copy the logic from the SQLT Parser, and if all else fails - default to 'restrict'
    # cache the result
    $delete_actions->{$rel} = $rels->{$rel}{attrs}{_delete_rekey_action} ||= do {
      my $action;
      my ($rev_rel_name, $rev_rel_info) = eval { %{$rsrc->reverse_relationship_info($rel)} };

      if (exists $rev_rel_info->{attrs}{on_delete}) {
        $action = $rev_rel_info->{attrs}{on_delete};
      }
      else {
        $action = 'cascade' if $rels->{$rel}{attrs}{cascade_delete};
      }

      $action = lc( $action||'' );
      $action =~ s/^\s+|\s+$//g;

      # default to restrict
      $action = 'restrict' unless ($action eq 'cascade' or $action eq 'set null' or $action eq 'no action');

      if ($action ne 'cascade' and $rels->{$rel}{attrs}{cascade_delete}) {
        $rsrc->related_source($rel)->source_name;
        carp_unique(sprintf 
            "Selected delete-action '%s' on reverse-relationship '%s' inconsistent with "
           ."'cascade_delete' setting on relationship '%s'. This will most likely result "
           .'in inconsistent storage state',
          $action,
          $rsrc->related_source($rel)->source_name . '/' . $rev_rel_name,
          $rsrc->source_name . '/' . $rel,
        );
      }

      $action;
    };
  }

  # cascades are taken care of by the dbic core
  delete $delete_actions->{$_} for grep {
    $delete_actions->{$_} eq 'no action' or $delete_actions->{$_} eq 'cascade'
  } keys %$delete_actions;

  if (keys %$delete_actions) {
    my $guard = $rsrc->schema->txn_scope_guard;

    # will be deleted by next::method
    my $storage_side_values = $self->{_column_data_in_storage} || {};

    # create a "clone" as if it was never updated, so we can chain properly
    # off of it
    # use a manual construct so that neither new() overrides nor FilterColumn
    # get in the way
    $self->get_columns; # this forces deflation of any inflated-only data present
    my $old_self = bless({
      _column_data => { %{$self->{_column_data} || {}}, %$storage_side_values },
      _in_storage => 1,
      _result_source => $rsrc,
    }, ref $self);

    # first delete the row itself, to allow server-side cascades
    $self->next::method(@rest);

    for my $rel (keys %$delete_actions) {
      my ($old_cond, $old_is_crosstable, $new_cond, $new_is_crosstable) = map {
        $rsrc->_resolve_condition(
          $rels->{$rel}{cond}, $rel, $_, $rel
        );
      } ($old_self, $self);

      # if a join is necessary it will not work - the original row is no longer there
      # as we udpated it in next::method above
      $self->throw_exception(sprintf
        "Unable to rekey '%s' - only join-free condition relationships are supported",
        $rsrc->source_name . '/' . $rel,
      ) if ($old_is_crosstable || $new_is_crosstable);

      my $rel_src = $rsrc->related_source($rel);
      my $rel_result = $rel_src->result_class;
      my $rel_rs = $rel_src->resultset->search($old_cond, { columns => [
        grep { $rel_result->_track_storage_value($_) } $rel_src->columns
      ]});

      if ($delete_actions->{$rel} eq 'restrict') {
        $self->throw_exception(sprintf
          "Delete violated ON DELETE RESTRICT constraint on relationship '%s'",
          $rsrc->source_name . '/' . $rel,
        ) if $rel_rs->count;
      }
      else {
        $rel_rs->update_all({map { $_ => undef } keys %$new_cond});
      }
    }

    $guard->commit;
  }
  else {
    $self->next::method(@rest);
  }

  return $self;
}

1;
