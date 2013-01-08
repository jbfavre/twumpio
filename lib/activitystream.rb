require_relative './activitystream/activities'
require_relative './activitystream/objects'

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

end
