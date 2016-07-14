Gem::Specification.new do |s|
  s.name        = 'rad-hoc'
  s.version     = '0.0.1'
  s.licenses    = ['MIT']
  s.summary     = "Ad hoc ActiveRecord Queries"
  s.description = "Library for custom reports generated from YAML query specifications"
  s.authors     = ["Gary Foster", "Stephen McIntosh", "Joshua Plicque"]
  s.email       = 'garyfoster@radicalbear.com'
  #s.files       = ["lib/"]
  #s.homepage    = 'https://github.com/radicalbear'

  s.add_dependency 'activerecord', '~> 4.2'
  s.add_dependency 'activesupport', '~> 4.2'
  s.add_dependency 'arel', '~> 6.0'

  s.add_development_dependency 'rspec', '~> 3.5'
  s.add_development_dependency 'factory_girl', '~> 4.7'
  s.add_development_dependency 'sqlite3', '~> 1.3'
  s.add_development_dependency 'simplecov', '~> 0.12'
end
