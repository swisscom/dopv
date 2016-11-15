require 'dopv/version'
require 'dopv/log'
require 'dopv/persistent_disk'
require 'dopv/plan'
require 'dopv/infrastructure'
require 'dop_common'

module Dopv
  def self.load_plan(plan_file)
    plan_parser = ::DopCommon::Plan.new(YAML::load_file(plan_file))
    ::Dopv::Plan.new(plan_parser)
  end

  def self.load_data_volumes_db(db_file)
    ::Dopv::PersistentDisk::load(db_file)
  end

  def self.run_plan(plan, data_volumes_db, action=:deploy, destroy_data_volumes=false)
    if plan.valid?
      nodes = plan.nodes
      case action
      when :deploy
        nodes.each { |n| ::Dopv::Infrastructure::bootstrap_node(n, data_volumes_db) }
      when :undeploy
        nodes.each { |n| ::Dopv::Infrastructure::destroy_node(n, data_volumes_db, destroy_data_volumes) }
      end
    end
  end

  def self.plan_valid?(plan_file)
    plan = load_plan(plan_file)
    plan.valid?
  end
end
