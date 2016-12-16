require 'spec_helper'
require 'securerandom'

describe Dopv::PersistentDisk::Entry do
  before(:each) do
    @disk_valid = {
      :name => 'disk-1',
      :id   => SecureRandom.uuid,
      :pool => 'pool-1',
      :node => 'foo.bar.baz',
      :size => 1024*1024*1024
    }
    @entry = Dopv::PersistentDisk::Entry.new(@disk_valid)
  end

  describe '#new' do
    it 'creates a new entry object from proper input' do
      expect(@entry).to be_an_instance_of(Dopv::PersistentDisk::Entry)
    end

    it 'will raise an exception if input is incorrect' do
      expect { Dopv::PersistentDisk::Entry.new({}) }.to \
        raise_error(Dopv::PersistentDisk::PersistentDiskError)
    end
  end

  %w(name id pool size node).each do |accessor|
    describe "##{accessor}" do
      it "responds to #{accessor}" do
        expect(@entry.respond_to?(:"#{accessor}")).to be true
      end

      it "returns entry's #{accessor}" do
        expect(@entry.send(:"#{accessor}")).to eq @disk_valid[:"#{accessor}"]
      end
    end
  end
end
