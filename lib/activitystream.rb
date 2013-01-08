require "oj"
require "multi_json"

module Utils
  def to_json
    hash = {}
    self.instance_variables.each do |var|
      hash[var.to_s.gsub!('@','')] = self.instance_variable_get var if self.instance_variable_get var
    end
    MultiJson.dump(hash, :pretty => true)
  end
end

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
