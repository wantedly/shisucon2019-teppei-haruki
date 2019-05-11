require 'redis'
require 'redis/connection/hiredis'

class RedisClient
  @@redis = (Thread.current[:isu_redis] ||= Redis.new(host: (ENV["REDIS_HOST"] || "127.0.0.1"), port: 6379))
  class << self

    def reset_htmlify_text
      keys = @@redis.keys(key_htmlify_text("*"))
      return if keys.empty?
      @@redis.del(*keys)
    end

    def initialize_htmlify_text(tweets)
      reset_htmlify_text

      htmlified_pairs = tweets.map do |tweet|
        htmlified = tweet['text']
          .gsub('&', '&amp;')
          .gsub('<', '&lt;')
          .gsub('>', '&gt;')
          .gsub('\'', '&apos;')
          .gsub('"', '&quot;')
          .gsub(/#(\S+)(\s|$)/, '<a class="hashtag" href="/hashtag/\1">#\1</a>\2')

        [key_htmlify_text(tweet['id']), htmlified]
      end

      return if htmlified_pairs.empty?
      @@redis.mset(*(htmlified_pairs.flatten))
    end

    def get_htmlify_text(tweet_id)
      @@redis.get(key_htmlify_text(tweet_id))
    end

    def set_htmlify_text(tweet_id, htmlified)
      @@redis.set(key_htmlify_text(tweet_id), htmlified)
    end

    private

    def key_htmlify_text(tweet_id)
      "isu:key_htmlify_text:#{tweet_id}"
    end
  end
end