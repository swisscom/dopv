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
