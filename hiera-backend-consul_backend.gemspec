require 'date'

Gem::Specification.new do |s|
  s.name        = 'hiera-backend-consul_backend'
  s.version     = '0.9.0'
  s.date        = Date.today
  s.summary     = 'A hiera backend to query consul'
  s.description = 'A hiera backend that queries consul\'s service discovery catalog and distributed k/v store'
  s.authors     = ['David Gwilliam', 'Marc Cluet']
  s.email       = 'dhgwilliam@gmail.com'
  s.files       = Dir.glob(File.join(File.dirname(__FILE__), 'lib', '**', '*'))
  s.homepage    = 'https://github.com/dhgwilliam/hiera-consul'
  s.license     = 'Apache 2.0'
  s.add_runtime_dependency 'json', ['>=1.1.1']
  s.add_runtime_dependency 'hiera', ['~>1.0']
  s.add_development_dependency 'rake'
  s.add_development_dependency 'puppet'
  s.add_development_dependency 'puppetlabs_spec_helper'
  s.add_development_dependency 'rspec', ['~>3.3']
  s.add_development_dependency 'pry'
  s.add_development_dependency 'webmock', ['~>1.22']
end
