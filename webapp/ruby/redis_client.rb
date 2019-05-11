require 'redis'
require 'redis/connection/hiredis'

class RedisClient
  @@redis = (Thread.current[:isu_redis] ||= Redis.new(host: (ENV["REDIS_HOST"] || "127.0.0.1"), port: 6379))
  class << self

    def initialize_user_id_to_name
      users = db.xquery(%|
        SELECT id,name
        FROM users
      |)

      user_key_pairs = users.map {|user| [key_user_id_to_name(user['id'], user['name'])] }
      return if user_key_pairs.empty?
      @@redis.mset(*(user_key_pairs.flatten))
    end

    private

    def key_user_id_to_name(user_id)
      "isu:user_id_to_name:#{user_id}"
    end
  end
end