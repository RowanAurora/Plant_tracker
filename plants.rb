# frozen_string_literal: true

require 'sinatra'
require 'sinatra/reloader'
require 'sinatra/content_for'
require 'tilt/erubis'
require 'pry'

# Light conditions could be a drop down with limited options

configure do
  enable :sessions
  set :erb, escape_html: true
  set :session_secret, SecureRandom.hex(32)
end

configure(:development) do
  require_relative 'database_persistence'
  also_reload 'database_persistence.rb'
end

before do
  @storage = DatabasePersistence.new(logger)
end

def gather_plant_info
  {
    common_name: params[:common_name],
    scientific_name: params[:scientific_name],
    water_frequency: params[:water_frequency],
    light: params[:light],
    room_name: params[:room_name]
  }
end

helpers do
  def does_plant_need_water(plant_id)
    if @storage.watered?(plant_id)
      'watered'
    else
      'water-me'
    end
  end
end

get '/' do
  redirect '/plants'
end

# home page, lists plants
get '/plants' do
  @rooms = @storage.find_all_rooms

  @plant_list = if params[:room_name]
                  @storage.find_all_plants_in_room(params[:room_name])
                else
                  @storage.find_all_plants
                end

  erb :home, layout: :layout
end

# page for creating new plant profile
get '/rooms' do
  @rooms = @storage.find_all_rooms

  erb :rooms, layout: :layout
end

post '/rooms/new' do
  @storage.create_room(params[:room_name])

  redirect '/rooms'
end

# Specific room page display
get '/rooms/:id' do
  @room = @storage.find_one_room(params[:id].to_i)

  erb :room, layout: :layout
end

# Specific Room page editing
post '/rooms/:id' do
  @storage.update_room(params[:room_name], params[:id].to_i)
  redirect "/rooms/#{params[:id]}"
end

# page for creating new plant profile
get '/plants/new' do
  @rooms = @storage.find_all_rooms

  erb :new, layout: :layout
end

# creates new plant profile
post '/plants/new' do
  @storage.new_plant(gather_plant_info)
  redirect '/plants'
end

# displays info of given plant
get '/plants/:id' do
  @plant = @storage.find_one_plant(params[:id])

  @descriptors = ['Common Name', 'Scientific Name', 'Water', 'Last Watered On', 'Light Conditions', 'In This Room']
  erb :plant, layout: :layout
end

# page for editing plant info
get '/plants/:id/edit' do
  @plant = @storage.find_one_plant(params[:id])
  @rooms = @storage.find_all_rooms
  erb :edit, layout: :layout
end

# updates plant info
post '/plants/:id/edit' do
  @storage.update_plant(params[:id].to_i, gather_plant_info)
  redirect '/plants'
end

# Updated specifically the last_watered value
post '/plants/:id/watered' do
  id = params[:id]
  @storage.water_plant(id)

  redirect "/plants/#{id}"
end

post '/delete/plant' do
  plant_id = params[:plant_id]
  room_id = @storage.find_room_id(params[:room_name])
  @storage.delete_plant(plant_id, room_id)
  redirect '/plants'
end

post '/delete/room' do
  room_id = params[:room_id]
  @storage.delete_room(room_id)
  redirect '/rooms'
end
