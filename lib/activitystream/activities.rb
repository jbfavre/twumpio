require "date"

module ActivityStream

  class Activity
    include Utils

    attr_reader :id, :url, :generator, :provider, :verb, :actor,
                :object, :published, :to, :cc, :bto, :bcc

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
      self.to_json
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

  class Follow < ActivityStream::Activity
    def initialize(event)
      # Twitter events: follow vs. unfollow
      # ActivityStream verbs: follow vs. stop-following
      @verb      = case event[:event]
                     'follow'   then 'follow'
                     'unfollow' then 'stop-following'
                   end
      @verb      = event[:event]
      @generator = { url: "http://pump.io/twumpio/" }
      @provider  = { url: "https://www.twitter.com" }
      @published = DateTime.parse("#{event[:created_at]}").rfc3339
      @actor     = ActivityStream::Actor.new(event[:source])
      @object    = ActivityStream::Actor.new(event[:target_object])
  end

end
