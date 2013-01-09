require 'oj'
require 'multi_json'

module Utils
  def to_json
    hash = {}
    self.instance_variables.each do |var|
      hash[var.to_s.gsub!('@','')] = self.instance_variable_get var if self.instance_variable_get var
    end
    MultiJson.dump(hash, :pretty => true)
  end
end
