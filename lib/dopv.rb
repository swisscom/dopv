require 'dopv/version'
require 'dopv/log'
require 'dopv/persistent_disk'
require 'dopv/plan'
require 'dopv/infrastructure'
require 'dopv/state_store'
require 'dop_common'
require 'etc'

module Dopv

  def self.valid?(plan_file)
    plan = DopCommon::Plan.new(YAML.load_file(plan_file))
    plan.valid?
  end

  def self.add(plan_file)
    raise StandardError, 'Plan not valid; did not add' unless valid?(plan_file)
    plan_store.add(plan_file)
  end

  def self.update_plan(plan_file, options = {})
    raise StandardError, 'Plan not valid; did not add' unless valid?(plan_file)
    plan_name = plan_store.update(plan_file)
    update_state(plan_name, options)
  end

  def self.update_state(plan_name, options = {})
    plan_store.run_lock(plan_name) do
      state_store = Dopv::StateStore.new(plan_name, plan_store)
      state_store.update(options)
    end
  end

  def self.remove(plan_name, remove_dopi_state = true, remove_dopv_state = false)
    plan_store.remove(plan_name, remove_dopi_state, remove_dopv_state)
  end

  def self.list
    plan_store.list
  end

  def self.deploy(plan_name)
    plan = get_plan(plan_name)
    state_store = Dopv::StateStore.new(plan_name, plan_store)
    plan_store.run_lock(plan_name) do
      plan.nodes.each do |node|
        Dopv::Infrastructure::bootstrap_node(node, state_store)
      end
    end
  end

  def self.undeploy(plan_name, destroy_data_volumes = false)
    plan = get_plan(plan_name)
    plan_store.run_lock(plan_name) do
      state_store = Dopv::StateStore.new(plan_name, plan_store)
      plan.nodes.each do |node|
        Dopv::Infrastructure::destroy_node(node, state_store, destroy_data_volumes)
      end
    end
  end

  def self.export_state(plan_name)
    ensure_plan_exists(plan_name)
    state_store = Dopv::StateStore.new(plan_name, plan_store)
    state_store.export
  end

  def self.export_state_file(plan_name, state_file)
    ensure_plan_exists(plan_name)
    File.open(state_file, 'w+') do |diskdb|
      diskdb << YAML.dump(Dopv.export_state(plan_name))
    end
  end

  def self.import_state(plan_name, data_volumes_db)
    ensure_plan_exists(plan_name)
    plan_store.run_lock(plan_name) do
      state_store = Dopv::StateStore.new(plan_name, plan_store)
      state_store.import(data_volumes_db)
    end
  end

  def self.import_state_file(plan_name, state_file)
    ensure_plan_exists(plan_name)
    Dopv.import_state(plan_name, YAML.load_file(state_file))
  end

  private

  def self.plan_store
    @plan_store ||= DopCommon::PlanStore.new(plan_store_dir)
  end

  def self.ensure_plan_exists(plan_name)
    unless plan_store.list.include?(plan_name)
      raise StandardError, "The plan #{plan_name} does not exist in the plan store"
    end
  end

  #TODO: repalace the state store location with the value from the unified configuration
  def self.plan_store_dir
      user = Etc.getpwuid(Process.uid)
      is_root = user.name == 'root'
      dop_home = File.join(user.dir, '.dop')
      @plan_store_dir = is_root ?
        '/var/lib/dop/cache' :
        File.join(dop_home, 'cache')
  end

  def self.get_plan(plan_name)
    raise StandardError, 'Please update the plan state, there are pending updates' if pending_updates?(plan_name)
    plan_parser = plan_store.get_plan(plan_name)
    Dopv::Plan.new(plan_parser)
  end

  def self.pending_updates?(plan_name)
    state_store = Dopv::StateStore.new(plan_name, plan_store)
    state_store.pending_updates?
  end
end
