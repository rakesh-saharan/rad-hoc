require 'spec_helper'

REJECTED_TABLES = ["schema_migrations", "brutals"]

module YAMLFixture
  def from_yaml(name)
    RadHoc::Processor.new(File.open(File.join(Bundler.root, "spec/fixtures/yaml/#{name}")).read, REJECTED_TABLES)
  end

  def from_literal(literal)
    RadHoc::Processor.new(literal, REJECTED_TABLES)
  end

  def rejected_tables
    REJECTED_TABLES
  end
end

RSpec.configure do |config|
  config.include YAMLFixture
end
