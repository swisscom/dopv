require 'dopv/version'
require 'dopv/log'
require 'dopv/persistent_disk'
require 'dopv/plan'
require 'dopv/infrastructure'
require 'dopv/state_store'
require 'dop_common'
require 'etc'
require 'parallel'

module Dopv
  extend DopCommon::NodeFilter

  DEFAULT_MAX_IN_FLIGHT = 5

  def self.valid?(plan_file)
    hash, _ = plan_store.read_plan_file(plan_file)
    plan = DopCommon::Plan.new(hash)
    plan.valid?
  end

  def self.add(plan_file)
    raise StandardError, 'Plan not valid; did not add' unless valid?(plan_file)
    plan_name = plan_store.add(plan_file)
    Dopv.update_state(plan_name)
    plan_name
  end

  def self.update_plan(plan_file, options = {})
    raise StandardError, 'Plan not valid; did not add' unless valid?(plan_file)
    plan_name = plan_store.update(plan_file)
    update_state(plan_name, options)
    plan_name
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

  def self.deploy(plan_name, options = {})
    ensure_plan_exists(plan_name)
    update_state(plan_name)
    plan = get_plan(plan_name)
    nodes = filter_nodes(plan.nodes, options[:run_for_nodes])
    state_store = Dopv::StateStore.new(plan_name, plan_store)
    plan_store.run_lock(plan_name) do
      in_parallel(plan, nodes) do |node|
        Dopv::Infrastructure::bootstrap_node(node, state_store)
      end
    end
  end

  def self.undeploy(plan_name, options = {})
    ensure_plan_exists(plan_name)
    update_state(plan_name)
    plan = get_plan(plan_name)
    nodes = filter_nodes(plan.nodes, options[:run_for_nodes])
    plan_store.run_lock(plan_name) do
      state_store = Dopv::StateStore.new(plan_name, plan_store)
      in_parallel(plan, nodes) do |node|
        Dopv::Infrastructure::destroy_node(node, state_store, options[:rmdisk])
      end
    end
  end

  def self.refresh(plan_name, options = {})
    ensure_plan_exists(plan_name)
    update_state(plan_name)
    plan = get_plan(plan_name)
    nodes = filter_nodes(plan.nodes, options[:run_for_nodes])
    plan_store.run_lock(plan_name) do
      state_store = Dopv::StateStore.new(plan_name, plan_store)
      in_parallel(plan, nodes) do |node|
        Dopv::Infrastructure::refresh_node(node, state_store)
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
    @plan_store ||= DopCommon::PlanStore.new(DopCommon.config.plan_store_dir)
  end

  def self.ensure_plan_exists(plan_name)
    unless plan_store.list.include?(plan_name)
      raise StandardError, "The plan #{plan_name} does not exist in the plan store"
    end
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

  def self.in_parallel(plan, nodes)
    errors = false
    infras = nodes.group_by {|node| node.infrastructure}
    Parallel.each(infras.keys, :in_threads => infras.keys.length) do |infra|
      Dopv.log.debug("Spawning control thread for infra #{infra.name}")
      max_in_flight = infra.max_in_flight || plan.max_in_flight || DEFAULT_MAX_IN_FLIGHT
      Dopv.log.debug("Threads for infra #{infra.name}: #{max_in_flight}")
      Parallel.each(infras[infra], :in_threads => max_in_flight) do |node|
        Dopv.log.debug("Spawning thread for node #{node.name}.")
        begin
          Dopv.log.debug("Yielding node #{node.name}.")
          yield(node)
        rescue => e
          errors = true
          Dopv.log.error("There was an error while processing node #{node.name}: #{e}")
          raise Parallel::Break
        end
      end
    end
    raise "Errors detected during plan run" if errors
  end

end
