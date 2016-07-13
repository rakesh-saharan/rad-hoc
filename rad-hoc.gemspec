Gem::Specification.new do |s|
  s.name        = 'rad-hoc'
  s.version     = '0.0.0'
  s.licenses    = ['MIT']
  s.summary     = "Ad hoc ActiveRecord Queries"
  s.description = "Library for custom reports generated from YAML query specifications"
  s.authors     = ["Gary Foster", "Stephen McIntosh"]
  s.email       = 'garyfoster@radicalbear.com'
  #s.files       = ["lib/"]
  #s.homepage    = ''

  s.add_dependency 'activerecord'
  s.add_dependency 'activesupport'
  s.add_dependency 'arel'

  s.add_development_dependency 'rspec'
  s.add_development_dependency 'factory_girl'
  s.add_development_dependency 'sqlite3'
end
