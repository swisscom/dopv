# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'dopv/version'

Gem::Specification.new do |spec|
  spec.name          = "dopv"
  spec.version       = Dopv::VERSION
  spec.authors       = ["Pavol Dilung"]
  spec.email         = ["pavol.dilung@swisscom.com"]
  spec.description   = %q{Deployment orchestrator for VMs}
  spec.summary       = %q{Deployment orchestrator for VMs}
  spec.homepage      = "https://gitlab.swisscloud.io/clu-dop/dopv/tree/master"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "pry"
  if RUBY_VERSION < 2
    spec.add_development_dependency "pry-debugger"
  else
    spec.add_development_dependency "pry-byebug"
  end

  spec.add_dependency "json", "~> 1.8"
  spec.add_dependency "colorize", "~> 0.7.5"
  spec.add_dependency "rest-client", "~> 1.7"
  spec.add_dependency "rbovirt", "~> 0.1.1"
  spec.add_dependency "rbvmomi", "~> 1.8.2"
  spec.add_dependency "net-ssh", "< 3.0" # fog dependcy but net-ssh >= 3.x require ruby 2.x
  spec.add_dependency "fog-google", "< 0.1.1" # fog dependcy but net-ssh >= 3.x require ruby 2.x
  spec.add_dependency "fog", "~> 1.31.0"
  spec.add_dependency "gli", "~> 2.13.1"
end
