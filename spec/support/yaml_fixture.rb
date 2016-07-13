require 'spec_helper'

module YAMLFixture
  def from_file(name)
    RadHoc.new(File.open(File.join(Bundler.root, "spec/fixtures/yaml/#{name}.yaml")))
  end

  def from_literal(literal)
    RadHoc.new(literal)
  end
end

RSpec.configure do |config|
  config.include YAMLFixture
end
