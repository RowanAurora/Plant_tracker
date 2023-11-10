# frozen_string_literal: true

require 'pg'

# methods for retrieving information from database
module Finders
  def find_all_plants
    result = query <<~SQL
      Select plants.*, rooms.room_name From plants
      LEFT OUTER JOIN plants_rooms ON plants.id = plant_id
      LEFT OUTER JOIN rooms ON plants_rooms.room_id = rooms.id;
    SQL
    parse_plant_info(result)
  end

  def find_all_plants_in_room(room_name)
    find_all_plants.select { |x| x[:room_name] == room_name }
  end

  def find_one_plant(plant_id)
    find_all_plants.select { |x| x[:id] == plant_id.to_i }[0]
  end

  def find_room_id(room_name)
    sql = 'SELECT id FROM rooms where room_name = $1'
    result = query(sql, room_name)

    result.map { |tuple| tuple['id'] }[0].to_i
  end

  def find_all_rooms
    sql = 'SELECT * FROM rooms;'
    result = query(sql)
    parse_room_info(result)
  end

  def find_one_room(id)
    sql = 'SELECT * FROM rooms WHERE id = $1;'
    result = query(sql, id)
    parse_room_info(result)[0]
  end
end

# methods that update databse
module Updators
  def update_plant(id, plant)
    query('UPDATE plants SET common_name = $1 where id = $2', plant[:common_name], id)
    query('UPDATE plants SET scientific_name = $1 where id = $2', plant[:scientific_name], id)
    query('UPDATE plants SET water_frequency = $1 where id = $2', plant[:water_frequency], id)
    query('UPDATE plants SET light = $1 where id = $2', plant[:light], id)
    sql2 = 'UPDATE plants_rooms SET room_id = (SELECT rooms.id FROM rooms WHERE room_name = $1) WHERE plant_id = $2'
    query(sql2, plant[:room_name], id)
  end

  def update_room(room_name, room_id)
    sql = 'UPDATE rooms SET room_name = $1 Where id = $2'
    query(sql, room_name, room_id)
  end

  def add_plant_to_room(plant_id, room_id)
    sql1 = 'DELETE FROM plants_rooms WHERE plant_id = $1 AND room_id = $2'
    query(sql1, plant_id, room_id)

    sql2 = 'INSERT INTO plants_rooms (plant_id, room_id) VALUES ($1, $2)'
    query(sql2, plant_id, room_id)
  end

  def water_plant(plant_id)
    sql = 'UPDATE plants SET last_watered = now() WHERE id = $1'
    query(sql, plant_id)
  end
end

# methods for adding info to database
module Creators
  def new_plant(info)
    sql = 'INSERT INTO plants ( common_name, scientific_name, water_frequency, light) VALUES ($1, $2, $3, $4);'
    query(sql, info[:common_name], info[:scientific_name], info[:water_frequency], info[:light])

    plant_id_result = query('SELECT max(id) as id FROM plants')
    id = plant_id_result.map { |tuple| tuple['id'] }[0].to_i

    sql2 = 'INSERT INTO plants_rooms (plant_id, room_id) values ($1, (SELECT rooms.id FROM rooms WHERE room_name = $2))'
    query(sql2, id, info[:room_name])
  end

  def create_room(room_name)
    sql = 'INSERT INTO rooms (room_name) VALUES ($1)'
    query(sql, room_name)
  end
end

# main class for functionality. Contains private Methods, deletion and watered?
class DatabasePersistence
  include Finders
  include Creators
  include Updators
  def initialize(logger)
    @db = PG.connect(dbname: 'plants')
    setup_schema
    @logger = logger
  end

  def delete_plant(plant_id, _room_id)
    sql1 = 'DELETE FROM plants_rooms WHERE plant_id = $1'
    query(sql1, plant_id)

    sql2 = 'DELETE FROM plants WHERE id = $1'
    query(sql2, plant_id)
  end

  def delete_room(room_id)
    sql1 = 'UPDATE plants_rooms SET room_id = (SELECT id FROM rooms WHERE id != $1 Limit 1) WHERE room_id = $1;'
    query(sql1, room_id)

    sql2 = 'DELETE FROM rooms WHERE id = $1'
    query(sql2, room_id)
  end

  def watered?(plant)
    current_day = Date.today
    last_water_day = Date.parse(plant[:last_watered])
    last_water_day + plant[:water_frequency].to_i >= (current_day)
  end

  private

  def parse_plant_info(result)
    result.map do |tuple|
      plant_id = tuple['id'].to_i

      { id: plant_id,
        common_name: tuple['common_name'],
        scientific_name: tuple['scientific_name'],
        water_frequency: tuple['water_frequency'],
        last_watered: tuple['last_watered'],
        light: tuple['light'],
        room_name: tuple['room_name'] }
    end
  end

  def parse_room_info(result)
    result.map do |tuple|
      id = tuple['id'].to_i
      { id:,
        room_name: tuple['room_name'] }
    end
  end

  def setup_schema
    result = @db.exec <<~SQL
      SELECT EXISTS ( SELECT 1 FROM pg_tables WHERE tablename = 'plants' ) AS table_existence;
    SQL

    return unless result.first['table_existence'] == 'f'

    plant_table
    room_table
    plants_rooms_table
    @db.exec("INSERT INTO rooms (room_name) VALUES ('Living Room')")
  end

  def plant_table
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
  end

  def room_table
    @db.exec <<~SQL
      CREATE TABLE rooms (
        id serial PRIMARY KEY,
        room_name text NOT NULL
      );

    SQL
  end

  def plants_rooms_table
    @db.exec <<~SQL
      CREATE TABLE plants_rooms (
        id serial PRIMARY KEY,
        plant_id int references plants(id) UNIQUE,
        room_id int references rooms(id)
      );
    SQL
  end

  def query(statement, *params)
    @logger.info("#{statement}: #{params}")
    @db.exec_params(statement, params)
  end
end
