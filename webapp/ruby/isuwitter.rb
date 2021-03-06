require 'digest/sha1'
require 'json'
require 'net/http'

require 'sinatra/base'
require 'sinatra/json'
require 'mysql2-cs-bind'
require 'erubis'

require 'rack-lineprof'
require 'logger' # このrequire要らないかも

require './redis_client'

module Isuwitter
  class WebApp < Sinatra::Base
    use Rack::Session::Cookie, key: 'isu_session', secret: 'kioicho'
    # use Rack::Lineprof, profile: 'isuwitter.rb', logger: Logger.new('/var/log/lineprof.log')
    set :public_folder, File.expand_path('../../public', __FILE__)

    PERPAGE = 50
    ISUTOMO_ENDPOINT = 'http://localhost:8081'

    helpers do
      def db
        Thread.current[:isuwitter_db] ||= Mysql2::Client.new(
          host: ENV['YJ_ISUCON_DB_HOST'] || 'localhost',
          port: ENV['YJ_ISUCON_DB_PORT'] ? ENV['YJ_ISUCON_DB_PORT'].to_i : 3306,
          username: ENV['YJ_ISUCON_DB_USER'] || 'root',
          password: ENV['YJ_ISUCON_DB_PASSWORD'],
          database: ENV['YJ_ISUCON_DB_NAME'] || 'isuwitter',
          reconnect: true,
        )
      end

      def initialize_htmlify
        db.xquery(%| SELECT id, text FROM tweets |).each do |tweet|
          db.xquery(%| UPDATE tweets SET html = ? WHERE id = ? |, htmlify(tweet['text']), tweet['id'])
        end
      end

      def get_all_tweets until_time, query
        if until_time
          db.xquery(%| SELECT * FROM tweets WHERE created_at < ? AND text LIKE "%#{query}%" ORDER BY created_at DESC LIMIT 50 |, until_time)
        else
          db.xquery(%| SELECT * FROM tweets WHERE text LIKE "%#{query}%" ORDER BY created_at DESC LIMIT 50 |)
        end
      end

      def get_friend_tweets until_time, friend_ids

        if until_time
          db.xquery(%|
            SELECT * 
            FROM tweets 
            WHERE created_at < ? 
            AND user_id IN (?)
            ORDER BY created_at DESC 
            LIMIT 50 |,
          until_time, friend_ids.map(&:to_i))
        else
          db.xquery(%|
            SELECT *
            FROM tweets
            WHERE user_id IN (?)
            ORDER BY created_at DESC 
            LIMIT 50 |,
          friend_ids.map(&:to_i))
        end
      end

      def get_user_id name
        user_name_to_id[name]
      end

      def get_user_name id
        user_id_to_name[id]
      end

      def htmlify text
        text ||= ''
        text
          .gsub('&', '&amp;')
          .gsub('<', '&lt;')
          .gsub('>', '&gt;')
          .gsub('\'', '&apos;')
          .gsub('"', '&quot;')
          .gsub(/#(\S+)(\s|$)/, '<a class="hashtag" href="/hashtag/\1">#\1</a>\2')
      end

      def user_id_to_name
        return Thread.current[:user_id_to_name] if Thread.current[:user_id_to_name]
        users = db.xquery(%|
          SELECT id,name
          FROM users
        |)

        Thread.current[:user_id_to_name] = {}
        users.each do |user|
          Thread.current[:user_id_to_name][user['id'].to_i] = user['name']
        end
        Thread.current[:user_id_to_name]
      end

      def user_name_to_id
        return Thread.current[:user_name_to_id] if Thread.current[:user_name_to_id]
        Thread.current[:user_name_to_id] = user_id_to_name.map {|k,v| [v,k]}.to_h
      end

      def get_friends user
        friends = db.xquery(%| SELECT * FROM friends WHERE me = ? |, user).first
        return nil unless friends
        friends['friends'].split(',')
      end

      def render_tweets(tweets)
        tweets.map do |tweet|
          <<~TEXT
            <div class="tweet" data-time="#{tweet['time']}">
              <p><a href="/#{tweet['name']}" class="tweet-user-name">#{tweet['name']}</a></p>
              <p>#{tweet['html']}</p>
              <p class="time">#{tweet['time']}</p>
            </div>
          TEXT
        end.join("\n")
      end
    end

    get '/' do
      @name = get_user_name session[:userId]
      if @name.nil?
        @flush = session[:flush]
        session.clear
        return erb :index, layout: :layout
      end

      friends = get_friends(@name)
      @tweets = []
      if friends
        friend_user_ids = friends.map {|friend_name| user_name_to_id[friend_name] }
        get_friend_tweets(params[:until], friend_user_ids.map(&:to_i)).each do |row|
          row['time'] = row['created_at'].strftime '%F %T'
          row['name'] = user_id_to_name[row['user_id']]
          @tweets.push row
        end
      end

      if params[:append]
        render_tweets(@tweets)
      else
        erb :index, layout: :layout
      end
    end

    post '/' do
      name = get_user_name session[:userId]
      text = params[:text]
      if name.nil? || text == ''
        redirect '/'
      end

      db.xquery(%|
        INSERT INTO tweets (user_id, text, html, created_at) VALUES (?, ?, ?, NOW())
      |, session[:userId], text, htmlify(text))

      redirect '/'
    end

    get '/initialize' do
      db.xquery(%| DELETE FROM tweets WHERE id > 100000 |)
      db.xquery(%| DELETE FROM users WHERE id > 1000 |)
      ok = system("mysql -u root -D isuwitter < #{Dir.pwd}/../sql/seed_isutomo.sql")
      ok = system("mysql -u root -D isutomo < #{Dir.pwd}/../sql/seed_isutomo.sql")
      halt 500, 'error' unless ok

      #initialize_htmlify

      res = { result: 'OK' }
      json res
    end

    post '/login' do
      name = params[:name]
      password = params[:password]

      user = db.xquery(%| SELECT * FROM users WHERE name = ? |, name).first
      unless user
        halt 404, 'not found'
      end

      sha1digest = Digest::SHA1.hexdigest(user['salt'] + password)
      if user['password'] != sha1digest
        session[:flush] = 'ログインエラー'
        redirect '/'
      end

      session[:userId] = user['id']
      redirect '/'
    end

    post '/logout' do
      session.clear
      redirect '/'
    end

    post '/follow' do
      name = get_user_name session[:userId]
      if name.nil?
        redirect '/'
      end

      user = params[:user]
      url = URI.parse "#{ISUTOMO_ENDPOINT}/#{name}"
      req = Net::HTTP::Post.new url.path
      req.set_form_data({'user' => user}, ';')
      res = Net::HTTP.start(url.host, url.port) do |http|
        http.request req
      end
      halt 500, 'error' if res.code != '200'

      redirect "/#{user}"
    end

    post '/unfollow' do
      name = get_user_name session[:userId]
      if name.nil?
        redirect '/'
      end

      user = params[:user]
      url = URI.parse "#{ISUTOMO_ENDPOINT}/#{name}"
      req = Net::HTTP::Delete.new url.path
      req.set_form_data({'user' => user}, ';')
      res = Net::HTTP.start(url.host, url.port) do |http|
        http.request req
      end
      halt 500, 'error' if res.code != '200'

      redirect "/#{user}"
    end

    def search session, params
      @name = get_user_name session[:userId]
      @query = params[:q]
      @query = "##{params[:tag]}" if params[:tag]

      @tweets = []
      get_all_tweets(params[:until],@query).each do |row|
        row['time'] = row['created_at'].strftime '%F %T'
        row['name'] = user_id_to_name[row['user_id']]
        @tweets.push row
      end

      if params[:append]
        erb :_tweets, layout: false
      else
        erb :search, layout: :layout
      end
    end

    get '/hashtag/:tag' do
      search session, params
    end

    get '/search' do
      search session, params
    end

    get '/:user' do
      @name = get_user_name session[:userId]
      @user = params[:user]
      @mypage = @name == @user

      user_id = get_user_id @user
      halt 404, 'not found' if user_id.nil?

      @is_friend = false
      if @name
        url = URI.parse "#{ISUTOMO_ENDPOINT}/#{@name}"
        req = Net::HTTP::Get.new url.path
        res = Net::HTTP.start(url.host, url.port) do |http|
          http.request req
        end
        friends = JSON.parse(res.body)['friends']
        @is_friend = friends.include? @user
      end

      if params[:until]
        rows = db.xquery(%|
          SELECT * FROM tweets WHERE user_id = ? AND created_at < ? ORDER BY created_at DESC LIMIT 50
        |, user_id, params[:until])
      else
        rows = db.xquery(%|
          SELECT * FROM tweets WHERE user_id = ? ORDER BY created_at DESC LIMIT 50
        |, user_id)
      end

      @tweets = []
      rows.each do |row|
        row['time'] = row['created_at'].strftime '%F %T'
        row['name'] = @user
        @tweets.push row
      end

      if params[:append]
        erb :_tweets, layout: false
      else
        erb :user, layout: :layout
      end
    end

  end
end
