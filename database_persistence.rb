require "pg"

class DatabasePersistence 
  def initialize(logger)
    @db = PG.connect(dbname: "plants")
    setup_schema
    @logger = logger
  end

  def new_plant(info)
    sql = "INSERT INTO plants ( common_name, scientific_name, water_frequency, light) VALUES ($1, $2, $3, $4);"
    query(sql, info[:common_name], info[:scientific_name], info[:water_frequency], info[:light])
   
    plant_id_result = query("SELECT max(id) as id FROM plants")
    id = plant_id_result.map { |tuple| tuple["id"] }[0].to_i

    sql_2 = "INSERT INTO plants_rooms (plant_id, room_id) values ($1, (SELECT rooms.id FROM rooms WHERE room_name = $2))"
    query(sql_2, id, info[:room_name])
  end

  def find_all_plants
    sql = "Select plants.*, rooms.room_name From plants LEFT OUTER JOIN plants_rooms ON plants.id = plant_id left outer JOIN rooms on plants_rooms.room_id = rooms.id;"
    result = query(sql)
    parse_plant_info(result)
  end

  def find_all_plants_in_room(room_id)
    sql = "Select plants.*, rooms.room_name From plants LEFT OUTER JOIN plants_rooms ON plants.id = plant_id LEFT OUTER JOIN rooms on room_id = rooms.id Where rooms.id = $1;"
    result = query(sql, room_id)
    parse_plant_info(result)
  end

  def find_one_plant(plant_id)
    sql = "Select plants.*, rooms.room_name From plants LEFT OUTER JOIN plants_rooms ON plants.id = plant_id left outer JOIN rooms on room_id = rooms.id Where plants.id = $1;"
    result = query(sql, plant_id)
    parse_plant_info(result)[0]
  end

  def find_room_id(room_name)
    sql = "SELECT id FROM rooms where room_name = $1"
    result = query(sql, room_name)

    id = result.map { |tuple| tuple["id"] }[0].to_i
  end

  def create_room(room_name)
    sql = "INSERT INTO rooms (room_name) VALUES ($1)"
    result = query(sql,room_name)
  end

  def add_plant_to_room(plant_id, room_id)
    sql_1 = "DELETE FROM plants_rooms WHERE plant_id = $1 AND room_id = $2"
    result = query(sql_1, plant_id, room_id)

    sql_2 = "INSERT INTO plants_rooms (plant_id, room_id) VALUES ($1, $2)"
    result = query(sql_2, plant_id, room_id)
  end

  def delete_plant(plant_id, room_id)
    sql_1 = "DELETE FROM plants_rooms WHERE plant_id = $1"
    result = query(sql_1, plant_id)

    sql_2 = "DELETE FROM plants WHERE id = $1"
    result = query(sql_2, plant_id)
  end

  def delete_room(room_id)
    sql_1 = "UPDATE plants_rooms SET room_id = (SELECT id FROM rooms WHERE id != $1 Limit 1) WHERE room_id = $1;"
    result = query(sql_1, room_id)

    sql_2 = "DELETE FROM rooms WHERE id = $1"
    result = query(sql_2, room_id)
  end

  def update_plant(id, plant)
    sql_1 = "UPDATE plants SET common_name = $1 where id = $2"
    sql_2 = "UPDATE plants SET scientific_name = $1 where id = $2"
    sql_3 = "UPDATE plants SET water_frequency = $1 where id = $2"
    sql_4 = "UPDATE plants SET light = $1 where id = $2"
    sql_5 = "UPDATE plants_rooms SET room_id = (SELECT rooms.id FROM rooms WHERE room_name = $1) WHERE plant_id = $2"
    info = [common_name = plant[:common_name],
            scientific_name = plant[:scientific_name],
            water_frequency = plant[:water_frequency],
            light = plant[:light]]
    counter = 0

    [sql_1, sql_2, sql_3, sql_4].each do |sql|
      query(sql, info[counter], id)
      counter += 1

    query(sql_5, plant[:room_name], id)
    end
  end

  def update_room(room_name, room_id)
    sql = "UPDATE rooms SET room_name = $1 Where id = $2"
    query(sql, room_name, room_id)
  end

  def find_all_rooms
    sql = "SELECT * FROM rooms;"
    result = query(sql)
    parse_room_info(result)
  end

  def find_one_room(id)
    sql = "SELECT * FROM rooms WHERE id = $1;"
    result = query(sql, id)
    parse_room_info(result)[0]
  end

  def water_plant(plant_id)
    sql = "UPDATE plants SET last_watered = now() WHERE id = $1"
    query(sql, plant_id)
  end

  def watered?(plant)
    result = query("SELECT now() as date")
    current_day = Date.today
    last_water_day = Date.parse(plant[:last_watered])
    last_water_day + plant[:water_frequency].to_i >= (current_day)
  end

  private

  def parse_plant_info(result)
    result.map do |tuple|
      plant_id = tuple["id"].to_i

      {id: plant_id, 
      common_name: tuple["common_name"], 
      scientific_name: tuple["scientific_name"],
      water_frequency: tuple["water_frequency"],
      last_watered: tuple["last_watered"],
      light: tuple["light"],
      room_name: tuple["room_name"]
      }
    end
  end

  def parse_room_info(result)
    result.map do |tuple|
      id = tuple["id"].to_i
      { id: id,
        room_name: tuple["room_name"]}
    end
  end

  def setup_schema
    result = @db.exec <<~SQL
    SELECT EXISTS ( SELECT 1 FROM pg_tables WHERE tablename = 'plants' ) AS table_existence;
    SQL

    if result.first["table_existence"] == "f"
      
      @db.exec <<~SQL
        CREATE TABLE plants (
          id serial PRIMARY KEY,
          Common_name text NOT NULL,
          scientific_name text NOT NULL,
          water_frequency int NOT NULL,
          last_watered date NOT NULL DEFAULT NOW(),
          light text NOT NULL
        );
      SQL

      @db.exec <<~SQL
        CREATE TABLE rooms (
          id serial PRIMARY KEY,
          room_name text NOT NULL
        );
      
      SQL
      @db.exec <<~SQL
        CREATE TABLE plants_rooms (
          id serial PRIMARY KEY,
          plant_id int references plants(id) UNIQUE,
          room_id int references rooms(id)
        );
        SQL
        @db.exec("INSERT INTO rooms (room_name) VALUES ('Living Room')")
    end
  end

  def query(statement, *params)
    @logger.info("#{statement}: #{params}")
    @db.exec_params(statement, params)
  end
end