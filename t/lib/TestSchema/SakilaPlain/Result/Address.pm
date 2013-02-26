use utf8;
package TestSchema::SakilaPlain::Result::Address;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'TestSchema::Sakila::BaseResult';
__PACKAGE__->table("address");
__PACKAGE__->add_columns(
  "address_id",
  {
    data_type => "smallint",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "address",
  { data_type => "varchar", is_nullable => 0, size => 50 },
  "address2",
  { data_type => "varchar", is_nullable => 1, size => 50 },
  "district",
  { data_type => "varchar", is_nullable => 0, size => 20 },
  "city_id",
  {
    data_type => "smallint",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "postal_code",
  { data_type => "varchar", is_nullable => 1, size => 10 },
  "phone",
  { data_type => "varchar", is_nullable => 0, size => 20 },
  "last_update",
  {
    data_type => "timestamp",
    datetime_undef_if_invalid => 1,
    default_value => \"current_timestamp",
    is_nullable => 0,
  },
);
__PACKAGE__->set_primary_key("address_id");
__PACKAGE__->belongs_to(
  "city",
  "TestSchema::SakilaPlain::Result::City",
  { city_id => "city_id" },
  { is_deferrable => 1, on_delete => "RESTRICT", on_update => "CASCADE" },
);
__PACKAGE__->has_many(
  "customers",
  "TestSchema::SakilaPlain::Result::Customer",
  { "foreign.address_id" => "self.address_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);
__PACKAGE__->has_many(
  "staffs",
  "TestSchema::SakilaPlain::Result::Staff",
  { "foreign.address_id" => "self.address_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);
__PACKAGE__->has_many(
  "stores",
  "TestSchema::SakilaPlain::Result::Store",
  { "foreign.address_id" => "self.address_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07033 @ 2013-02-26 11:28:18
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:VTjABhYeXRYj2l2nQRA7rg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
