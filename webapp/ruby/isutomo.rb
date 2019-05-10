require 'sinatra/base'
require 'sinatra/json'
require 'mysql2-cs-bind'
require 'json'

module Isutomo
  class WebApp < Sinatra::Base

    helpers do
      def db
        Thread.current[:isutomo_db] ||= Mysql2::Client.new(
          host: ENV['YJ_ISUCON_DB_HOST'] || 'localhost',
          port: ENV['YJ_ISUCON_DB_PORT'] ? ENV['YJ_ISUCON_DB_PORT'].to_i : 3306,
          username: ENV['YJ_ISUCON_DB_USER'] || 'root',
          password: ENV['YJ_ISUCON_DB_PASSWORD'],
          database: ENV['YJ_ISUCON_DB_NAME'] || 'isutomo',
          reconnect: true,
        )
      end

      def get_friends user
        friends = db.xquery(%| SELECT * FROM friends WHERE me = ? |, user).first
        return nil unless friends
        friends['friends'].split(',')
      end

      def set_friends user, friends
        db.xquery(%|
          UPDATE friends SET friends = ? WHERE me = ?
        |, friends.join(','), user)
      end
    end

    get '/initialize' do
      ok = system("mysql -u root -D isutomo < #{Dir.pwd}/../sql/seed_isutomo.sql")
      halt 500, 'error' unless ok
      res = { result: 'OK' }
      json res
    end

    get '/:me' do
      me = params[:me]
      friends = get_friends(me)
      halt 500, 'error' unless friends

      res = { friends: friends }
      json res
    end

    post '/:me' do
      me = params[:me]
      new_friend = params[:user]
      friends = get_friends me
      halt 500, 'error' unless friends

      if friends.include? new_friend
        halt 500, new_friend + ' is already your friends.'
      end

      friends.push new_friend
      set_friends me, friends
      res = { friends: friends }
      json res
    end

    delete '/:me' do
      me = params[:me]
      del_friend = params[:user]
      friends = get_friends me
      unless friends.include? del_friend
        halt 500, del_friend + ' is not your friends.'
      end

      friends.delete del_friend
      set_friends me, friends
      res = { friends: friends }
      json res
    end
  end
end
