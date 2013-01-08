module Twumpio
  class Frontend
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
        @feed.items = []
        # Convert status into Activity and add it to activities list
        @feed.items.push(ActivityStream::Activity.new(status.attrs))

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
        @feed.items = []
        # Convert status into Activity and add it to activity list
        @feed.items.push(ActivityStream::Favorite.new(event))
        # Publish Feed to PubSub backend
        publishToBackend
        puts "[twumpio::stream] incoming event: user @#{event[:source][:screen_name]} favorited status ##{event[:target_object][:id]} from @#{event[:target_object][:user][:screen_name]}"
      end
      @stream.on_event(:unfavorite) do |event|
        @feed.items = []
        # Convert status into Activity and add it to activity list
        @feed.items.push(ActivityStream::Favorite.new(event))
        # Publish Feed to PubSub backend
        publishToBackend
        puts "[twumpio::stream] incoming event: user @#{event[:source][:screen_name]} unfavorited status ##{event[:target_object][:id]} from @#{event[:target_object][:user][:screen_name]}"
      end
      @stream.on_event(:follow) do |event|
        puts "[twumpio::stream] incoming event: user @#{event[:source][:screen_name]} followed user @#{event[:target][:screen_name]}"
        @feed.items = []
        # Convert status into Activity and add it to activity list
        @feed.items.push(ActivityStream::Favorite.new(event))
        # Publish Feed to PubSub backend
        publishToBackend
      end
      @stream.on_event(:unfollow) do |event|
        puts "[twumpio::stream] incoming event: user @#{event[:source][:screen_name]} unfollowed user @#{event[:target][:screen_name]}"
        @feed.items = []
        # Convert status into Activity and add it to activity list
        @feed.items.push(ActivityStream::Favorite.new(event))
        # Publish Feed to PubSub backend
        publishToBackend
      end
      @stream.on_delete do |message|
        @feed.items = []
        # Convert status into Activity and add it to activity list
        @feed.items.push(ActivityStream::Delete.new(message))
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
        if @feed.items.length > 1
          new_last_status = @feed.items.first.id
        else
          new_last_status = nil
        end

        # API calls should stop if no activities
        if @feed.items.length > 1
          # API calls shoud stop if last status id is the same as max_id
          until @feed.items.last.id == rest_options[:max_id]
            api_calls += 1
            # update max_id with last activity id to avoid duplicate statuses
            # and/or infinite loop
            rest_options[:max_id] = @feed.items.last.id
            # Get home_timeline with new params options
            callTwitterHomeTimeline(rest_options)
          end
          puts "[twumpio::rest] incoming ##{@feed.items.length} statuses returned in ##{api_calls} API calls"
          # reverse sort activities array to have the oldest one at first place
          @feed.items.reverse!
          publishToBackend
          @feed.items = []
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
          # Can't empty @feed.items here since we could have many statuses to process
          # then have to reverse sort activities list to get activities in proper order
          # before being able to push them to backend

          # Convert status into Activity and add it to activities list
          #activity = TwitterStatusToActivity.new(status.attrs)
          activity = ActivityStream::Activity.new(status.attrs)
          @feed.items.push(activity)

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
        @backend.set("tweetin::last_status", @feed.items.last.id) if defined?(@feed.items.last.id)
      rescue => error
        try += 1
        puts "[twumpio::backend] backend '#{error}'. Retrying"
        sleep 1
        retry if try <= 3
      end
    end

  end

end
