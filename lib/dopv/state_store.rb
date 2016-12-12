#
# This is the DOPv disk state store
#
module Dopv
  class StateStore

    def initialize(plan_name, plan_store)
      @plan_store  = plan_store
      @plan_name   = plan_name
      @state_store = @plan_store.state_store(plan_name, 'dopv')
    end

    def update(options = {})
      if options[:clear]
        clear(options)
      elsif options[:ignore]
        ignore(options)
      else
        update_state(options)
      end
    rescue DopCommon::UnknownVersionError => e
      Dopv.log.warn("The state had an unknown plan version #{e.message}, ignoring update")
      ignore(options)
    rescue => e
      Dopv.log.error("An error occured during update: #{e.message}")
      Dopv.log.error("Please update with the 'clear' or 'ignore' option")
    end

    def export
      @state_store.transaction(true) do
        @state_store[:data_volumes] || {}
      end
    end

    def import(data_volumes)
      @state_store.transaction do
        @state_store[:data_volumes] = data_volumes
      end
    end

    def method_missing(m, *args, &block)
      @state_store.send(m, *args, &block)
    end

    private

    def clear(options)
      @state_store.transaction do
        Dopv.log.debug("Clearing the disk state for plan #{@plan_name}")
        ver = @plan_store.show_versions(@plan_name).last
        @state_store[:data_volumes] = {}
        @state_store[:version] = ver
      end
    end

    def ignore(options)
      @state_store.transaction do
        ver = @plan_store.show_versions(@plan_name).last
        Dopv.log.debug("Ignoring update and setting disk state version of plan #{@plan_name} to #{ver}")
        @state_store[:version] = ver
      end
    end

    def update_state(options)
      @state_store.update do |plan_diff|
        Dopv.log.debug("Updating disk state for plan #{@plan_name}. This is the diff:")
        Dopi.log.debug(plan_diff.to_s)
        #TODO: Add update logic for plan updates here
      end
    end

  end

  class StateStoreObserver

    def initialize(plan, state_store)
      @plan        = plan
      @state_store = state_store
    end

    def update(notify_only = false)
      @state_store.persist_state(@plan)
    end

  end
end
