use utf8;
package TestSchema::SakilaPlain::Result::FilmText;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'TestSchema::Sakila::BaseResult';
__PACKAGE__->table("film_text");
__PACKAGE__->add_columns(
  "film_id",
  { data_type => "smallint", is_nullable => 0 },
  "title",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "description",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("film_id");


# Created by DBIx::Class::Schema::Loader v0.07033 @ 2013-02-26 11:28:18
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:jBh+XK7s5d6OuF1z5ryW0A


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
