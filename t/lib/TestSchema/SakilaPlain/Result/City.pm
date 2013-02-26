use utf8;
package TestSchema::SakilaPlain::Result::City;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'TestSchema::Sakila::BaseResult';
__PACKAGE__->table("city");
__PACKAGE__->add_columns(
  "city_id",
  {
    data_type => "smallint",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "city",
  { data_type => "varchar", is_nullable => 0, size => 50 },
  "country_id",
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
__PACKAGE__->set_primary_key("city_id");
__PACKAGE__->has_many(
  "addresses",
  "TestSchema::SakilaPlain::Result::Address",
  { "foreign.city_id" => "self.city_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);
__PACKAGE__->belongs_to(
  "country",
  "TestSchema::SakilaPlain::Result::Country",
  { country_id => "country_id" },
  { is_deferrable => 1, on_delete => "RESTRICT", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07033 @ 2013-02-26 11:28:18
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:b7XuuWxItb1mLESEH+XPHQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
