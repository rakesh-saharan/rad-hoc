require 'spec_helper'

module YAMLFixture
=begin
  def from_file(name)
    RadHoc.new(File.open(File.join(Bundler.root, "spec/fixtures/yaml/#{name}.yaml")))
  end
=end

  def from_literal(literal)
    RadHoc.new(literal)
  end
end

RSpec.configure do |config|
  config.include YAMLFixture
end
