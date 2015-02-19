module Fog
  module Compute
    class Ovirt
      class Volumes < Fog::Collection
        def all(filters = {})
          if vm.is_a? Fog::Compute::Ovirt::Server
            load service.list_vm_volumes(vm.id)
          elsif vm.is_a? Fog::Compute::Ovirt::Template
            load service.list_template_volumes(vm.id)
          else
            load service.list_volumes
          end
        end
      end
    end
  end
end
