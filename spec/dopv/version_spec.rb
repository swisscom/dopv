require 'spec_helper'

describe Dopv::VERSION do
  it 'should defined' do
    expect(defined?(Dopv::VERSION))
  end

  it 'should be a string' do
    expect(Dopv::VERSION).to be_kind_of(String)
  end

  it 'should be a string that respects semantic versioning' do
    # Borrowed from https://github.com/mojombo/semver/issues/32#issuecomment-7663411
    semver_re = /^(\d+\.\d+\.\d+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$/
    expect(Dopv::VERSION).to match(semver_re)
  end
end
