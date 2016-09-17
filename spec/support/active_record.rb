require 'active_record'
require 'active_support'

# File created with help from http://www.iain.nl/testing-activerecord-in-isolation

#ActiveRecord::Base.logger = Logger.new(STDERR)
=begin
def setup_postgres
  config = {
    database: 'rad-hoc_test',
    adapter: 'postgresql'
  }
  ActiveRecord::Base.establish_connection config.merge(database: nil)
  ActiveRecord::Base.connection.drop_database config[:database]
  ActiveRecord::Base.connection.create_database config[:database], {charset: 'utf8'}
  ActiveRecord::Base.establish_connection config
end
=end

def setup_sqlite3
  ActiveRecord::Base.establish_connection(
    adapter: 'sqlite3',
    database: ':memory:'
  )
end
setup_sqlite3

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
  belongs_to :owner, polymorphic: true

  scope :published, -> { where(published: true) }

  def self.is_published(b)
    where(published: b)
  end
end

class Track < ActiveRecord::Base
  belongs_to :album
  has_one :performer, through: :album

  scope :published, -> { where(published: true) }
  scope :best_title, -> { where(title: "Best Title") }

  def self.is_published(b)
    where(published: b)
  end
end

class Performer < ActiveRecord::Base
  has_many :albums
end

class Record < ActiveRecord::Base
  has_many :albums, as: :owner
end

class Company < ActiveRecord::Base

end

class Member < ActiveRecord::Base
  belongs_to :security_group
end

class SecurityGroup < ActiveRecord::Base

end