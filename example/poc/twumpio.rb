require "daemons"
require "redis"
require "hiredis"
require "twitter"
require "tweetstream"
require "date"
require "oj"
require "json"
require "multi_json"
require "open-uri"
require "timeout"


trap(:INT) { puts; exit }

# Implements PubSub against Redis with sort of persistence
#
#class PubSubRedis < Redis
#
#  def initialize(options = {})
#    @timestamp = options[:timestamp].to_i || 0 # 0 means -- no backlog needed
#    super
#  end
#
#  # Add each event to a Sorted Set with the timestamp as the score
#  def publish(channel, message)
#    timestamp = Time.now.to_i
#    zadd(channel, timestamp, MultiJson.encode([channel, message]))
#    super(channel, MultiJson.encode(message))
#  end
#
#  # returns the backlog of pending messages [ event, payload ] pairs
#  # We do a union of sorted sets because we need to support wild-card channels.
#  def backlog(channels, &block)
#    return if @timestamp == 0
#
#    # Collect the entire set of events with wild-card support.
#    events = channels.collect {|e| keys(e)}.flatten
#
#    return if not events or events.empty? # no events to process
#
#    destination = "backlog-#{Time.now.to_i}"
#    zunionstore(destination, events)
#    # We want events only after the timestamp so add the (. This ensures that
#    # an event with this timestamp will not be sent.
#    # TODO: We may have a condition where, multiple events for the same timestamp
#    # may be recorded but will be missed out because of the (.
#    messages = zrangebyscore(destination, "(#{@timestamp.to_s}", "+inf")
#
#    messages.each do |message|
#      event, payload = MultiJson.decode(message)
#      block.call(event, payload)
#    end
#
#    # cleanup
#    del(destination)
#  end
#end

class ActivityFeed
  attr_accessor :activities

  def initialize
    @activities = []
  end

  def getActivities()
    JSON.dump(self)
  end
  def self.json_create(o)
    new(*o['items']['activities'])
  end
  def to_json(*a)
    { 'items' => activities }.to_json(*a)
  end
end

class TwitterUsertoActor
  attr_reader :id, :url, :objecttype, :displayname, :image

  def initialize(user)
    @id  = "acct:#{user[:screen_name]}@twitter.com"
    @url = "https://www.twitter.com/#{user[:screen_name]}"
    @objecttype = 'person'
    @displayname = "#{user[:name]}"
    @image = [{ url: "#{user[:profile_image_url]}", height: 48, width:48 },
              { url: "#{user[:profile_image_url_https]}", height: 48, width:48 }]
  end

  def self.json_create(o)
    new(*o['id'], *o['url'], *o['objecttype'], *o['displayname'], *o['image'])
  end
  def to_json(*a)
    { 'id' => @id, 'url' => @url, 'objectType' => @objecttype,
      'displayName' => @displayname, 'image' => @image }.to_json(*a)
  end
end

class TwitterStatusToActivity
  attr_reader :id, :url, :generator, :provider, :verb, :actor, :object, :cc, :published

  def initialize(status)
    @id        = status[:id]
    @verb      = 'post'
    @url       = "https://www.twitter.com/statuses/#{status[:id].to_s}"
    @generator = { url: "http://pump.io/twumpio/" }
    @provider  = { url: "https://www.twitter.com" }
    @published = DateTime.parse("#{status[:created_at]}").rfc3339
    @actor     = TwitterUsertoActor.new(status[:user])
    @cc        = nil

    status[:text].gsub!("\n", " ")
    links      = extractLinksFromEntities(status[:entities])

    if status.has_key?(:retweeted_status)
      @verb   = 'share'
      @object = TwitterStatusToActivity.new(status[:retweeted_status]).to_hash
      @object[:objectType] = 'activity'

    elsif status[:in_reply_to_status_id]
      @object[:objectType] = 'comment'
      @object[:in_reply_to] = {
        id: status[:in_reply_to_status_id],
        objectType: 'note',
        url: "https://www.twitter.com/statuses/#{status[:in_reply_to_status_id].to_s}"
      }

    else
      if status[:entities].has_key?(:media)
        medium = status[:entities][:media][0]
        @object = {
          id: medium[:id],
          objectType: 'image',
          title: expandTwitterUrl(status[:text], links),
          image: { url: "#{medium[:media_url]}" },
          fullImage: { url: "#{medium[:media_url]}" },
          url: "#{medium[:expanded_url]}"
        }
        @cc = processUserMention(status[:entities])

      else
        @object = {
          id: status[:id],
          objectType: 'note',
          content: expandTwitterUrl(status[:text], links)
        }
        @cc = processUserMention(status[:entities])

      end
    end

    # If it's a reply, we have to add in_reply_to into object
    # and change objectType
    if status[:in_reply_to_status_id]
      @object[:objectType] = 'comment'
      @object[:in_reply_to] = {
        id: status[:in_reply_to_status_id],
        objectType: 'note',
        url: "https://www.twitter.com/statuses/#{status[:in_reply_to_status_id].to_s}"
      }

    end

  end

  def extractLinksFromEntities(entities)
    links = []
    if entities.has_key?(:urls) && entities[:urls].length > 0
      entities[:urls].each do | link |
        # replace t.co url with expanded one
        result = { indices: link[:indices], real_url: link[:expanded_url] }
        links.push(result)
      end
    end
    if entities.has_key?(:media) && entities[:media].length > 0
      entities[:media].each do | medium |
        # delete t.co url since media will be embedded and displayed
        result = { indices: medium[:indices], real_url: '' }
        links.push(result)
      end
    end
    links = links.sort_by{ |url| url[:indices] }.reverse!
  end

  def expandTwitterUrl(text, links)
    links.each do |url|
      first = url[:indices][0]
      last  = url[:indices][1] - 1
      text[first..last] = "#{url[:real_url]}"
    end
    text.strip!
    text
  end

  def processUserMention(entities)
    cc = []
    entities[:user_mentions].each do | mention |
      cc << {
        id: "acct:#{mention[:screen_name]}@twitter.com",
        displayName: "#{mention[:name]}",
        objectType: "person"
      }
    end
    if cc.length > 0
      cc
    else
      nil
    end
  end

  def to_hash()
    MultiJson.load(self.getActivity, :symbolize_keys => true)
  end
  def getActivity()
    JSON.dump(self)
  end
  def self.json_create(o)
    new(*o['id'], *o['url'], *o['generator'], *o['provider'], *o['verb'], *o['actor'], *o['object'], *o['cc'], *o['published'])
  end
  def to_json(*a)
    { 'id' => @id, 'url' => @url, 'generator' => @generator, 'provider' => @provider, 'verb' => @verb, 'actor' => @actor, 'object' => @object, 'cc' => @cc, 'published' => @published }.to_json(*a)
  end
end

class TwitterFavoriteToActivity
  attr_reader :verb, :generator, :provider, :published, :actor, :object

  def initialize(event)
    @verb      = event[:event]
    @generator = { url: "http://pump.io/twumpio/" }
    @provider  = { url: "https://www.twitter.com" }
    @published = DateTime.parse("#{event[:created_at]}").rfc3339
    @actor     = TwitterUsertoActor.new(event[:source])
    @object    = TwitterStatusToActivity.new(event[:target_object])
  end

  def self.json_create(o)
    new(*o['verb'], *o['generator'], *o['provider'], *o['published'], *o['actor'], *o['object'])
  end
  def to_json(*a)
    { 'verb' => @verb, 'generator' => @generator, 'provider' => @provider, 'published' => @published, 'actor' => @actor, 'object' => @object }.to_json(*a)
  end
end

class Twumpio

  attr_reader :feed, :backend, :stream, :restapi

  def initialize(params)
    @twitter_params = params[:twitter]
    @backend_params = params[:pubsub]
    # Create Activity Feed
    @feed = ActivityFeed.new
    # Initialize Redis backend
    # TODO - use persistent backlog as described here:
    # http://blog.joshsoftware.com/2011/01/03/do-you-need-a-push-notification-manager-redis-pubsub-to-the-rescue/
    @backend = Redis.new(@backend_params)
    puts "[twumpio::backend] Backend initialized"
    # Configure Twitter RestAPI
    initTwitterRest
    # Configure Twitter StreamAPI
    initTwitterStream
    # Start Twitter calls
    startTwitter
  end

  def initTwitterRest
    Twitter.configure do |config|
      config.consumer_key       = @twitter_params[:consumer_key]
      config.consumer_secret    = @twitter_params[:consumer_secret]
      config.oauth_token        = @twitter_params[:oauth_token]
      config.oauth_token_secret = @twitter_params[:oauth_token_secret]
    end
  end

  def initTwitterStream
    TweetStream.configure do |config|
      config.consumer_key       = @twitter_params[:consumer_key]
      config.consumer_secret    = @twitter_params[:consumer_secret]
      config.oauth_token        = @twitter_params[:oauth_token]
      config.oauth_token_secret = @twitter_params[:oauth_token_secret]
    end
    @stream = TweetStream::Daemon.new('twumpio::stream', { ARGV: ['start'], multiple: false, monitor: true, log_output: true, ontop: true, } )

    @stream.on_timeline_status do |status|
      # Empty activities list
      @feed.activities = []
      # Convert status into Activity and add it to activities list
      activity = TwitterStatusToActivity.new(status.attrs)
      @feed.activities.push(activity)

      if status.attrs.has_key?(:media) || (status.attrs[:retweeted_status] && status.attrs[:retweeted_status].has_key?(:media))
        puts "\n\n======================================="
        puts MultiJson.dump(status.attrs, :pretty => true)
        puts "=======================================\n\n"
      end

      if status.attrs[:retweeted_status]
        puts "[twumpio::stream] incoming status ##{status.id.to_s} from @#{status.user.screen_name}"
        puts "[twumpio::stream] ##{status.id.to_s} is retweet of ##{status.retweeted_status.id.to_s}"
        if status.media.length > 0
          puts "[twumpio::stream] media spotted into ##{status.retweeted_status.id.to_s}"
        end
      elsif status.attrs[:in_reply_to_status_id]
        puts "[twumpio::stream] incoming status ##{status.id.to_s} from @#{status.user.screen_name}"
        puts "[twumpio::stream] ##{status.id.to_s} is reply to ##{status.in_reply_to_status_id.to_s}"
        if status.media.length > 0
          puts "[twumpio::stream]  media into ##{status.id.to_s}"
        end
      else
        puts "[twumpio::stream] incoming status ##{status.id.to_s} from @#{status.user.screen_name}"
        if status.media.length > 0
          puts "[twumpio::stream] media into ##{status.id.to_s}"
        end
      end

      # Publish Feed to PubSub backend
      publishToBackend
    end

    @stream.on_inited do
      puts "[twumpio::stream] connection to userstream API established"
    end
    @stream.on_error do |message|
      puts "[twumpio::stream] incoming error '#{message}'"
    end
    @stream.on_reconnect do |timeout, retries|
      puts "[twumpio::stream] incoming connection closed. Trying to reconnect ##{retries}, timeout #{timeout}"
    end
    @stream.on_limit do |discarded_count|
      puts "[twumpio::stream] incoming rate limit notice for ##{discarded_count} tweets"
    end
    @stream.on_delete do |message|
      puts "[twumpio::stream] status ##{message} has been deleted"
    end
    @stream.on_unauthorized do |message|
      puts "[twumpio::stream] incoming HTTP 401\n#{message.inspect}\n\n"
    end
    @stream.on_direct_message do |message|
      puts "[twumpio::stream] incoming direct message:\n#{message.inspect}"
    end
    @stream.on_friends do |friends|
      puts "[twumpio::stream] incoming friend list. Discarding"
    end
    @stream.on_no_data_received do |message|
      puts "[twumpio::stream] incoming got no data for 90 seconds. Discarding\n#{message.inspect}\n\n"
    end
    @stream.on_enhance_your_calm do |message|
      puts "[twumpio::stream] incoming HTTP 420\n#{message.inspect}\n\n"
    end
    @stream.on_stall_warning do |message|
      puts "[twumpio::stream] incoming stall_warning message. Discarding\n#{message.inspect}\n\n"
    end
    # Full event's list can be found here:
    # https://dev.twitter.com/docs/streaming-apis/messages#Events_event
    @stream.on_event(:favorite) do |event|
      @feed.activities = []
      # Convert status into Activity and add it to activity list
      @feed.activities.push(TwitterFavoriteToActivity.new(event))
      # Publish Feed to PubSub backend
      publishToBackend
      puts "[twumpio::stream] incoming event: user @#{event[:source][:screen_name]} favorited status ##{event[:target_object][:id]} from @#{event[:target_object][:user][:screen_name]}"
    end
    @stream.on_event(:unfavorite) do |event|
      puts "[twumpio::stream] incoming event: user @#{event[:source][:screen_name]} unfavorited status ##{event[:target_object][:id]} from @#{event[:target_object][:user][:screen_name]}"
    end
    @stream.on_event(:follow) do |event|
      puts "[twumpio::stream] incoming event: user @#{event[:source][:screen_name]} followed user @#{event[:target][:screen_name]}"
    end
    @stream.on_event(:unfollow) do |event|
      puts "[twumpio::stream] incoming event: user @#{event[:source][:screen_name]} unfollowed user @#{event[:target][:screen_name]}"
      puts "\n\n#{MultiJson.dump(event, :pretty => true)}\n\n"
    end
    @stream.on_event(:block) do |event|
      puts "[twumpio::stream] incoming event: user @#{event[:source][:screen_name]} blocked user @#{event[:target][:screen_name]}"
    end
    @stream.on_event(:unblock) do |event|
      puts "[twumpio::stream] incoming event: user @#{event[:source][:screen_name]} blocked user @#{event[:target][:screen_name]}"
    end
    #@stream.on_anything do |message|
    #  puts "Got 'something': #{message.inspect}\n\n"
    #end
  end

  def startTwitter
    # Try to get the last seen status id
    last_status = @backend.get("tweetin::last_status")

    # If 'last_status' defined, means that we already pulled statuses in the past
    # Some statuses could be missing. Try to get them back
    if last_status
      puts "[twumpio::rest] since_id = #{last_status}"

      # Set API options
      rest_options = {
        count: 200,
        since_id: last_status,
        include_rts: true,
        include_entities: true,
        exclude_replies: false,
        trim_user: false
      }
      api_calls = 0

      # Get home_timeline for missing statuses
      callTwitterHomeTimeline(rest_options)

      # Store first activity id to update last_status at the ends
      if @feed.activities.length > 1
        new_last_status = @feed.activities.first.id
      else
        new_last_status = nil
      end

      # API calls should stop if no activities
      if @feed.activities.length > 1
        # API calls shoud stop if last status id is the same as max_id
        until @feed.activities.last.id == rest_options[:max_id]
          api_calls += 1
          # update max_id with last activity id to avoid duplicate statuses
          # and/or infinite loop
          rest_options[:max_id] = @feed.activities.last.id
          # Get home_timeline with new params options
          callTwitterHomeTimeline(rest_options)
        end
        puts "[twumpio::rest] incoming ##{@feed.activities.length} statuses returned in ##{api_calls} API calls"
        # reverse sort activities array to have the oldest one at first place
        @feed.activities.reverse!
        publishToBackend
        @feed.activities = []
      else
        puts "[twumpio::rest] nothing pending"
      end
      puts "[twumpio::rest] Switching to StreamingAPI now"
    end
    # Seems it does not work for now :(
    # https://github.com/intridea/tweetstream/issues/106
    #@stream.userstream( :stall_warnings => 'true', :replies => 'all', :with => 'following' )
    @stream.userstream
  end

  def callTwitterHomeTimeline(options)
    begin
      statuses = Twitter.home_timeline(options)
      statuses.each do |status |
        # Can't empty @feed.activities here since we could have many statuses to process
        # then have to reverse sort activities list to get activities in proper order
        # before being able to push them to backend

        # Convert status into Activity and add it to activities list
        activity = TwitterStatusToActivity.new(status.attrs)
        @feed.activities.push(activity)

        if status.attrs[:retweeted_status]
          puts "[twumpio::rest] incoming status ##{status.id.to_s} from @#{status.user.screen_name}"
          puts "[twumpio::rest] ##{status.id.to_s} is retweet of ##{status.retweeted_status.id.to_s}"
        elsif status.attrs[:in_reply_to_status_id]
          puts "[twumpio::rest] incoming status ##{status.id.to_s} from @#{status.user.screen_name}"
          puts "[twumpio::rest] ##{status.id.to_s} is reply to ##{status.in_reply_to_status_id.to_s}"
        else
          puts "[twumpio::rest] incoming status ##{status.id.to_s} from @#{status.user.screen_name}"
        end
        if status.media.length > 0
          puts "[twumpio::rest] media found into ##{status.id.to_s}"
        end
      end
      # Can't publish activies to backend now since we could have many other statuses to process
      # then have to reverse sort activities list to get activities in proper order
      # before being able to push them to backend
    rescue Twitter::Error::TooManyRequests => error
      # NOTE: Your process could go to sleep for up to 15 minutes but if you
      # retry any sooner, it will almost certainly fail with the same exception.
      puts "[twumpio::restapi] RateLimit exceeded. Waiting #{error.rate_limit.reset_in} seconds"
      sleep error.rate_limit.reset_in
      puts "[twumpio::restapi] RateLimit should be over. Retrying now"
      retry
    end
  end

  def publishToBackend
    # publish activities onto backend
    try = 0
    begin
      # TODO - use persistent backlog as described here:
      # http://blog.joshsoftware.com/2011/01/03/do-you-need-a-push-notification-manager-redis-pubsub-to-the-rescue/
      @backend.publish(:tweetin, @feed.getActivities)
    rescue => error
      try += 1
      puts "[twumpio::backend] backend '#{error}'. Retrying"
      sleep 1
      retry if try <= 3
    end

    try = 0
    begin
      # Update last_status on backend since they have been pushed to backend
      # of course, only update what needs to be: 'events' don't & they don't have any id
      @backend.set("tweetin::last_status", @feed.activities.last.id) if defined?(@feed.activities.last.id)
    rescue => error
      try += 1
      puts "[twumpio::backend] backend '#{error}'. Retrying"
      sleep 1
      retry if try <= 3
    end
  end

end

params = { twitter: { consumer_key:       '',
                      consumer_secret:    '',
                      oauth_token:        '',
                      oauth_token_secret: '' },
           pubsub:  { host: 'localhost', port: 6379, timeout: 0, tcp_keepalive: true } }
Twumpio.new(params)
