require 'spec_helper'
require 'yaml'

describe Dopv::Plan do
  before(:each) do
    plan_file = 'spec/data/plans/test-plan-1.yaml'
    plan_parser = DopCommon::Plan.new(YAML.load_file(plan_file))
    @plan = Dopv::Plan.new(plan_parser)
  end

  describe '#new' do
    it 'should create a plan object' do
      expect(@plan).to be_a Dopv::Plan
    end
  end

  describe '#name' do
    it 'is called test-1' do
      expect(@plan.name).to eq 'test-1'
    end
  end

  describe '#nodes' do
    it 'creates two nodes' do
      expect(@plan.nodes.length).to eq 2
    end
  end

  describe '#valid?' do
    it 'is a valid plan' do
      expect(@plan.valid?).to eq true
    end
  end
end
