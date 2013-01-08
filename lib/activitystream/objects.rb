require 'date'

module ActivityStream

  class Object
    include Utils
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

  end

  class Note < ActivityStream::Object
    attr_reader :content

    def initialize(status, content)
      @id         = status[:id]
      @url        = buildTwitterUrl('status', status[:id])
      @objecttype = 'note'

      @content    = content
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

  end
end
