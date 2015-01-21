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
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
end
