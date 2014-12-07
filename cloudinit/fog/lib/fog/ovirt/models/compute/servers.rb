require 'fog/core/collection'
require 'fog/ovirt/models/compute/server'

module Fog
  module Compute
    class Ovirt
      class Servers < Fog::Collection
        model Fog::Compute::Ovirt::Server

        def all(filters = {})
          load service.list_virtual_machines(filters)
        end

        def get(id)
          new service.get_virtual_machine(id)
        end

        def bootstrap(new_attributes = {})
          server = create(new_attributes)
          server.wait_for { stopped? }
          if new_attributes[:cloudinit].is_a?(Hash)
            server.cloudinit(new_attributes[:cloudinit])
          else
            server.start
          end
          server
        end
      end
    end
  end
end
