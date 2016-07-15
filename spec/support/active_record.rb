require 'active_record'
require 'active_support'
require 'sqlite3'

# File created with help from http://www.iain.nl/testing-activerecord-in-isolation

#ActiveRecord::Base.logger = Logger.new(STDERR)

ActiveRecord::Base.establish_connection(
    adapter: 'sqlite3',
    database: ':memory:'
)

RSpec.configure do |config|
  config.around do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end

load 'spec/fixtures/schema.rb'

class Album < ActiveRecord::Base
  has_many :tracks
  belongs_to :performer
  belongs_to :owner, class_name: "Record"
end

class Track < ActiveRecord::Base
  belongs_to :album
  has_one :performer, through: :album
end

class Performer < ActiveRecord::Base
  has_many :albums
end

class Record < ActiveRecord::Base
  has_many :albums
end
