use utf8;
package TestSchema::Sakila::Result::Language;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->load_components("Shadow");
__PACKAGE__->table("language");
__PACKAGE__->add_columns(
  "language_id",
  {
    data_type => "tinyint",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "name",
  { data_type => "char", is_nullable => 0, size => 20 },
  "last_update",
  {
    data_type => "timestamp",
    datetime_undef_if_invalid => 1,
    default_value => \"current_timestamp",
    is_nullable => 0,
  },
);
__PACKAGE__->set_primary_key("language_id");
__PACKAGE__->has_many(
  "film_languages",
  "TestSchema::Sakila::Result::Film",
  { "foreign.language_id" => "self.language_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);
__PACKAGE__->has_many(
  "film_original_languages",
  "TestSchema::Sakila::Result::Film",
  { "foreign.original_language_id" => "self.language_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07033 @ 2013-02-25 15:05:21
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:eXYb2FRWHve96chXk7aG2Q


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
