require 'spec_helper'

module YAMLFixture
  def from_yaml(name)
    RadHoc::Processor.new(File.open(File.join(Bundler.root, "spec/fixtures/yaml/#{name}")))
  end

  def from_literal(literal)
    RadHoc::Processor.new(literal)
  end
end

RSpec.configure do |config|
  config.include YAMLFixture
end
