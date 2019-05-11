require 'redis'
require 'redis/connection/hiredis'

class RedisClient
  @@redis = (Thread.current[:isu_redis] ||= Redis.new(host: (ENV["REDIS_HOST"] || "127.0.0.1"), port: 6379))
  class << self

    def initialize_user_id_to_name(users)
      user_key_pairs = users.map {|user| [key_user_id_to_name(user['id']), user['name']] }
      return if user_key_pairs.empty?
      @@redis.mset(*(user_key_pairs.flatten))
    end

    def initialize_user_name_to_id(users)
      user_key_pairs = users.map {|user| [key_user_name_to_id(user['name']), user['id']] }
      return if user_key_pairs.empty?
      @@redis.mset(*(user_key_pairs.flatten))
    end

    def get_user_id_to_name(user_id)
      @@redis.get(key_user_id_to_name(user_id))
    end

    def get_user_name_to_id(user_name)
      @@redis.get(key_user_name_to_id(user_name))
    end

    private

    def key_user_id_to_name(user_id)
      "isu:user_id_to_name:#{user_id}"
    end

    def key_user_name_to_id(user_name)
      "isu:user_name_to_id:#{user_name}"
    end
  end
end
