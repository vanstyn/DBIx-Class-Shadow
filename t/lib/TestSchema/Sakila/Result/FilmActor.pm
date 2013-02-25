use utf8;
package TestSchema::Sakila::Result::FilmActor;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->load_components("Shadow");
__PACKAGE__->table("film_actor");
__PACKAGE__->add_columns(
  "actor_id",
  {
    data_type => "smallint",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "film_id",
  {
    data_type => "smallint",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "last_update",
  {
    data_type => "timestamp",
    datetime_undef_if_invalid => 1,
    default_value => \"current_timestamp",
    is_nullable => 0,
  },
);
__PACKAGE__->set_primary_key("actor_id", "film_id");
__PACKAGE__->belongs_to(
  "actor",
  "TestSchema::Sakila::Result::Actor",
  { actor_id => "actor_id" },
  { is_deferrable => 1, on_delete => "RESTRICT", on_update => "CASCADE" },
);
__PACKAGE__->belongs_to(
  "film",
  "TestSchema::Sakila::Result::Film",
  { film_id => "film_id" },
  { is_deferrable => 1, on_delete => "RESTRICT", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07033 @ 2013-02-25 15:05:21
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:4bKaOoDvapCCrGG2y3wgZA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
