use utf8;
package TestSchema::SakilaPlain::Result::Payment;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'TestSchema::Sakila::BaseResult';
__PACKAGE__->table("payment");
__PACKAGE__->add_columns(
  "payment_id",
  {
    data_type => "smallint",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "customer_id",
  {
    data_type => "smallint",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "staff_id",
  {
    data_type => "tinyint",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "rental_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "amount",
  { data_type => "decimal", is_nullable => 0, size => [5, 2] },
  "payment_date",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
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
__PACKAGE__->set_primary_key("payment_id");
__PACKAGE__->belongs_to(
  "customer",
  "TestSchema::SakilaPlain::Result::Customer",
  { customer_id => "customer_id" },
  { is_deferrable => 1, on_delete => "RESTRICT", on_update => "CASCADE" },
);
__PACKAGE__->belongs_to(
  "rental",
  "TestSchema::SakilaPlain::Result::Rental",
  { rental_id => "rental_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "SET NULL",
    on_update     => "CASCADE",
  },
);
__PACKAGE__->belongs_to(
  "staff",
  "TestSchema::SakilaPlain::Result::Staff",
  { staff_id => "staff_id" },
  { is_deferrable => 1, on_delete => "RESTRICT", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07033 @ 2013-02-26 11:28:18
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:r8xBkB40tuHSiNe/Rn5uLg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
