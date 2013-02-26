use utf8;
package TestSchema::SakilaPlain::Result::Country;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'TestSchema::Sakila::BaseResult';
__PACKAGE__->table("country");
__PACKAGE__->add_columns(
  "country_id",
  {
    data_type => "smallint",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "country",
  { data_type => "varchar", is_nullable => 0, size => 50 },
  "last_update",
  {
    data_type => "timestamp",
    datetime_undef_if_invalid => 1,
    default_value => \"current_timestamp",
    is_nullable => 0,
  },
);
__PACKAGE__->set_primary_key("country_id");
__PACKAGE__->has_many(
  "cities",
  "TestSchema::SakilaPlain::Result::City",
  { "foreign.country_id" => "self.country_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07033 @ 2013-02-26 11:28:18
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:FBB09wc6oAR5gdH+gwx6Zw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
