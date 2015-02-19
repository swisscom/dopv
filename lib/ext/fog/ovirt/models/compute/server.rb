module Fog
  module Compute
    class Ovirt
      class Server < Fog::Compute::Server
        def attach_volume attrs
          wait_for { stopped? } if attrs[:blocking]
          service.attach_volume(id, attrs)
        end

        def detach_volume attrs
          wait_for { stopped? } if attrs[:blocking]
          service.detach_volume(id, attrs)
        end
      end
    end
  end
end
