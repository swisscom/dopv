module Fog
  module Compute
    class Ovirt < Fog::Service
      request :list_volumes, 'ext/fog/ovirt/requests/compute'
      request :attach_volume, 'ext/fog/ovirt/requests/compute'
      request :detach_volume, 'ext/fog/ovirt/requests/compute'
    end
  end
end
