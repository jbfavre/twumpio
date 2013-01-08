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

module ActivityStream

  class Feed
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

  class Activity
    attr_reader :id, :url, :generator, :provider, :verb, :actor, :object, :published
    attr_reader :to, :cc, :bto, :bcc

    def initialize(status)
      @id        = status[:id]
      @verb      = 'post'
      @url       = "https://www.twitter.com/statuses/#{status[:id].to_s}"
      @generator = { url: "http://pump.io/twumpio/" }
      @provider  = { url: "https://www.twitter.com" }
      @published = DateTime.parse("#{status[:created_at]}").rfc3339
      @actor     = ActivityStream::Actor.new(status[:user])
      @cc        = nil

      status[:text].gsub!("\n", " ")
      links      = extractLinksFromEntities(status[:entities])

      if status.has_key?(:retweeted_status)
        @verb   = 'share'
        @object = ActivityStream::Activity.new(status[:retweeted_status]).to_hash
        @object[:objectType] = 'activity'

      else
        if status[:entities].has_key?(:media)
          @object = ActivityStream::Image.new(status, expandTwitterUrl(status[:text], links))
          @cc = processUserMention(status[:entities])

        elsif status[:in_reply_to_status_id]
            @object = ActivityStream::Comment.new(status, expandTwitterUrl(status[:text], links))
            @cc = processUserMention(status[:entities])

        else
          @object = ActivityStream::Note.new(status, expandTwitterUrl(status[:text], links))
          @cc = processUserMention(status[:entities])

        end
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
        cc << ActivityStream::Actor.new(mention)
      end
      if cc.length > 0
        cc
      end
    end

    def to_hash()
      MultiJson.load(self.getActivity, :symbolize_keys => true)
    end
    def getActivity()
      JSON.dump(self)
    end
    def self.json_create(o)
      new(*o['id'], *o['url'], *o['generator'], *o['provider'],
          *o['verb'], *o['actor'], *o['object'], *o['to'], *o['cc'],
          *o['bto'], *o['bcc'], *o['published'])
    end
    def to_json(*a)
      { 'id' => @id, 'url' => @url, 'generator' => @generator, 'provider' => @provider,
        'verb' => @verb, 'actor' => @actor, 'object' => @object, 'to' => @to, 'cc' => @cc,
        'bto' => @bto, 'bcc' => @bcc, 'published' => @published }.to_json(*a)
    end
  end

  class Favorite < ActivityStream::Activity
    def initialize(event)
      @verb      = event[:event]
      @generator = { url: "http://pump.io/twumpio/" }
      @provider  = { url: "https://www.twitter.com" }
      @published = DateTime.parse("#{event[:created_at]}").rfc3339
      @actor     = ActivityStream::Actor.new(event[:source])
      @object    = ActivityStream::Activity.new(event[:target_object]).to_hash
      @object[:objectType] = 'activity'
    end
  end

  class Delete < ActivityStream::Activity
    def initialize(status_id)
      @verb = 'delete'
      @object   = { id: status_id, objectType: 'note' }
    end
  end








  class Object
    attr_reader :id, :url, :objecttype

    def buildTwitterUrl(type, stub)
      case type
        when 'user'   then "https://www.twitter.com/#{stub}"
        when 'status' then "https://www.twitter.com/statuses/#{stub.to_s}"
      end
    end
    def buildTwitterId(type, stub)
      case type
        when 'user'   then "acct:#{stub}@twitter.com"
      end
    end
  end

  class Actor < ActivityStream::Object
    attr_reader :displayname, :image

    def initialize(user)
      @id  = buildTwitterId('user', user[:screen_name])
      @url = buildTwitterUrl('user', user[:screen_name])
      @objecttype = 'person'

      @displayname = "#{user[:name]}"
      if user.has_key?(:profile_image_url) &&
         user.has_key?(:profile_image_url_https) &&
        @image = [{ url: "#{user[:profile_image_url]}", height: 48, width:48 },
                  { url: "#{user[:profile_image_url_https]}", height: 48, width:48 }]
      end
    end

    def self.json_create(o)
      new(*o['id'], *o['url'], *o['objecttype'], *o['displayname'], *o['image'])
    end
    def to_json(*a)
      { 'id' => @id, 'url' => @url, 'objectType' => @objecttype,
        'displayName' => @displayname, 'image' => @image }.to_json(*a)
    end
  end

  class Image < ActivityStream::Object
    attr_reader :title, :image, :fullimage

    def initialize(status, title)
      medium = status[:entities][:media][0]
      @id         = medium[:id]
      @url        = "#{medium[:expanded_url]}"
      @objecttype = 'image'

      @title      = title
      @image      = { url: "#{medium[:media_url]}" }
      @fullimage  = { url: "#{medium[:media_url]}" }
    end

    def self.json_create(o)
      new(*o['id'], *o['url'], *o['objecttype'], *o['title'], *o['image'], *o['fullimage'])
    end
    def to_json(*a)
      { 'id' => @id, 'url' => @url, 'objectType' => @objecttype,
        'title' => @title, 'image' => @image, 'fullimage' => @fullimage }.to_json(*a)
    end
  end

  class Note < ActivityStream::Object
    attr_reader :content

    def initialize(status, content)
      @id         = status[:id]
      @url        = buildTwitterUrl('status', status[:id])
      @objecttype = 'note'

      @content    = content
    end

    def self.json_create(o)
      new(*o['id'], *o['url'], *o['objecttype'], *o['content'])
    end
    def to_json(*a)
      { 'id' => @id, 'url' => @url, 'objectType' => @objecttype,
        'content' => @content }.to_json(*a)
    end
  end

  class Comment < ActivityStream::Object
    attr_reader :in_reply_to

    def initialize(status, content)
      @id          = status[:id]
      @url         = buildTwitterUrl('status', status[:id])
      @objecttype  = 'comment'

      @content     = content
      @in_reply_to = {
        id: status[:in_reply_to_status_id],
        objectType: 'note',
        url: buildTwitterUrl('status', status[:in_reply_to_status_id])
      }
    end

    def self.json_create(o)
      new(*o['id'], *o['url'], *o['objecttype'], *o['in_reply_to'], *o['content'])
    end
    def to_json(*a)
      { 'id' => @id, 'url' => @url, 'objectType' => @objecttype,
        'in_reply_to' => @in_reply_to, 'content' => @content }.to_json(*a)
    end
  end

end

class Twumpio

  attr_reader :feed, :backend, :stream, :restapi

  def initialize(params)
    @twitter_params = params[:twitter]
    @backend_params = params[:pubsub]
    # Create Activity Feed
    #@feed = ActivityFeed.new
    @feed = ActivityStream::Feed.new
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
    
    # Handle incoming events
    @stream.on_timeline_status do |status|
      # Empty activities list
      @feed.activities = []
      # Convert status into Activity and add it to activities list
      @feed.activities.push(ActivityStream::Activity.new(status.attrs))

      puts "[twumpio::stream] incoming status ##{status.id.to_s} from @#{status.user.screen_name}"
      if status.media.length > 0
        puts "[twumpio::stream] ##{status.id.to_s} contains media"
      end
      if status.attrs[:retweeted_status]
        puts "[twumpio::stream] ##{status.id.to_s} is retweet of ##{status.retweeted_status.id.to_s}"
      elsif status.attrs[:in_reply_to_status_id]
        puts "[twumpio::stream] ##{status.id.to_s} is reply to ##{status.in_reply_to_status_id.to_s}"
      end

      # Publish Feed to PubSub backend
      publishToBackend
    end
    # Full event's list can be found here:
    # https://dev.twitter.com/docs/streaming-apis/messages#Events_event
    @stream.on_event(:favorite) do |event|
      @feed.activities = []
      # Convert status into Activity and add it to activity list
      @feed.activities.push(ActivityStream::Favorite.new(event))
      # Publish Feed to PubSub backend
      publishToBackend
      puts "[twumpio::stream] incoming event: user @#{event[:source][:screen_name]} favorited status ##{event[:target_object][:id]} from @#{event[:target_object][:user][:screen_name]}"
    end
    @stream.on_event(:unfavorite) do |event|
      @feed.activities = []
      # Convert status into Activity and add it to activity list
      @feed.activities.push(ActivityStream::Favorite.new(event))
      # Publish Feed to PubSub backend
      publishToBackend
      puts "[twumpio::stream] incoming event: user @#{event[:source][:screen_name]} unfavorited status ##{event[:target_object][:id]} from @#{event[:target_object][:user][:screen_name]}"
    end
    @stream.on_delete do |message|
      @feed.activities = []
      # Convert status into Activity and add it to activity list
      @feed.activities.push(ActivityStream::Delete.new(message))
      # Publish Feed to PubSub backend
      publishToBackend
      puts "[twumpio::stream] ##{message} has been deleted"
    end










    @stream.on_inited do
      puts "[twumpio::stream] connection to userstream API established"
    end
    @stream.on_error do |message|
      puts "[twumpio::stream] incoming error '#{message}'"
    end
    @stream.on_reconnect do |timeout, retries|
      puts "[twumpio::stream] incoming stream closed. Trying to reconnect ##{retries}, timeout #{timeout}"
    end
    @stream.on_limit do |discarded_count|
      puts "[twumpio::stream] incoming rate limit notice for ##{discarded_count} tweets"
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
    
    
    
    
    
    
    
    
    
    
    @stream.on_event(:follow) do |event|
      puts "[twumpio::stream] incoming event: user @#{event[:source][:screen_name]} followed user @#{event[:target][:screen_name]}"
      puts "\n\n========================================"
      puts MultiJson.dump(event, :pretty => true)
      puts "========================================\n\n"
    end
    @stream.on_event(:unfollow) do |event|
      puts "[twumpio::stream] incoming event: user @#{event[:source][:screen_name]} unfollowed user @#{event[:target][:screen_name]}"
      puts "\n\n========================================"
      puts MultiJson.dump(event, :pretty => true)
      puts "========================================\n\n"
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
        #activity = TwitterStatusToActivity.new(status.attrs)
        activity = ActivityStream::Activity.new(status.attrs)
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
