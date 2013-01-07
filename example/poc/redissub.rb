require "redis"
require "multi_json"
require "oj"

redis = Redis.new

trap(:INT) { puts; exit }

begin
  redis.subscribe(:tweetin) do |on|
    on.subscribe do |channel, subscriptions|
      puts "Subscribed to ##{channel} (#{subscriptions} subscriptions)"
    end

    on.message do |channel, message|
      puts MultiJson.dump(MultiJson.load(message, :symbolize_keys => true), :pretty => true)
      puts "\n"
    end

    on.unsubscribe do |channel, subscriptions|
      puts "Unsubscribed from ##{channel} (#{subscriptions} subscriptions)"
    end
  end
rescue Redis::BaseConnectionError => error
  puts "#{error}, retrying in 1s"
  sleep 1
  retry
end
