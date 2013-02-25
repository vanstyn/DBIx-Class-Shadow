use utf8;
package TestSchema::Sakila::Result::Rental;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->load_components("Shadow");
__PACKAGE__->table("rental");
__PACKAGE__->add_columns(
  "rental_id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "rental_date",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 0,
  },
  "inventory_id",
  {
    data_type => "mediumint",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "customer_id",
  {
    data_type => "smallint",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "return_date",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "staff_id",
  {
    data_type => "tinyint",
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
__PACKAGE__->set_primary_key("rental_id");
__PACKAGE__->add_unique_constraint("rental_date", ["rental_date", "inventory_id", "customer_id"]);
__PACKAGE__->belongs_to(
  "customer",
  "TestSchema::Sakila::Result::Customer",
  { customer_id => "customer_id" },
  { is_deferrable => 1, on_delete => "RESTRICT", on_update => "CASCADE" },
);
__PACKAGE__->belongs_to(
  "inventory",
  "TestSchema::Sakila::Result::Inventory",
  { inventory_id => "inventory_id" },
  { is_deferrable => 1, on_delete => "RESTRICT", on_update => "CASCADE" },
);
__PACKAGE__->has_many(
  "payments",
  "TestSchema::Sakila::Result::Payment",
  { "foreign.rental_id" => "self.rental_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);
__PACKAGE__->belongs_to(
  "staff",
  "TestSchema::Sakila::Result::Staff",
  { staff_id => "staff_id" },
  { is_deferrable => 1, on_delete => "RESTRICT", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07033 @ 2013-02-25 15:05:21
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:aJmeZ2s2HAaKrhwhI/HCZQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
