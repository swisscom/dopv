# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'dopv/version'

Gem::Specification.new do |spec|
  spec.name          = 'dopv'
  spec.version       = Dopv::VERSION
  spec.authors       = ['Pavol Dilung', 'Andreas Zuber', 'Christian Schefuss']
  spec.email         = ['pavol.dilung@swisscom.com', 'azuber@puzzle.ch', 'christian.schefuss@swisscom.com']
  spec.description   = %q{Deployment orchestrator for VMs}
  spec.summary       = %q{Deployment orchestrator for VMs}
  spec.homepage      = 'https://github.com/swisscom/dopv'
  spec.license       = 'Apache-2.0'

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 1.9.3'

  spec.add_development_dependency 'bundler', '~> 1.3'
  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec-command'
  spec.add_development_dependency 'rspec-mocks'
  spec.add_development_dependency 'rspec'
  # Code quality
  spec.add_development_dependency 'simplecov'

  if RUBY_VERSION < '2'
    spec.add_development_dependency 'pry-debugger'
  else
    spec.add_development_dependency 'pry-byebug'
  end

  # Newer guard listen versions do not work properly with RB <= 2.2.2
  spec.add_development_dependency 'listen', '~> 3.0.8'
  spec.add_development_dependency 'guard-ctags-bundler'
  
  spec.add_dependency 'dop_common', '~> 0.15', '>= 0.15.3'
  spec.add_dependency 'fog', '~> 1.36.0'
  spec.add_dependency 'gli', '~> 2.13.1'
  spec.add_dependency 'json', '>= 1.8', '< 3.0'
  spec.add_dependency 'logger-colors', '~> 1'
  spec.add_dependency 'rbovirt', '~> 0.1', '>= 0.1.3'
  spec.add_dependency 'rbvmomi', '~> 1.8.2'
  spec.add_dependency 'parallel', '~> 1'
  spec.add_dependency 'hashdiff', '~> 0.3', '0.3.8'

  if RUBY_VERSION < '2'
    spec.add_dependency 'rest-client', '< 2.0'
  end

  if RUBY_VERSION < '2.3.0'
    spec.add_dependency 'nokogiri', '1.8.5'
    spec.add_dependency 'fog-xenserver', '0.2.3'
  else
    spec.add_dependency 'nokogiri', '>= 1.10.8'
  end
end
