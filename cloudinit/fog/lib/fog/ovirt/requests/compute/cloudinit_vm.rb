module Fog
  module Compute
    class Ovirt
      class Real
        def cloudinit_vm(id, options = {})
          raise ArgumentError, "instance id is a required parameter" unless id

          client.cloudinit_vm(id, options)
        end
      end

      class Mock
        def cloudinit_vm(id, options = {})
          raise ArgumentError, "instance id is a required parameter" unless id
          true
        end
      end
    end
  end
end

# vim:ts=2:sw=2:expandtab
