module CartoDB

  PUBLIC_DB_USER = 'publicuser'

  GOOGLE_SRID = 3785

  SRID = 4326

  TYPES = {
    "number"  => ["integer", "real", "double precision"],
    "string"  => ["varchar", "character varying", "text", "character varying(255)"],
    "date"    => ["timestamp", "timestamp without time zone"],
    "boolean" => ["boolean"]
  }

  module API

    VERSION_1 = "v1"

  end

end