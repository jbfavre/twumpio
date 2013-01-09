require_relative './activitystream/activities'
require_relative './activitystream/objects'

module ActivityStream

  class Feed
    include Utils

    attr_accessor :items

    def initialize
      @items = []
    end

    def getActivities()
      self.to_json
    end
  end

end
