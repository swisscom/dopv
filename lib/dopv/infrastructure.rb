require 'dopv/infrastructure/providers/base'

module Dopv
  module Infrastructure
    TMP = '/tmp'

    PROVIDER_BASE = 'dopv/infrastructure/providers'

    PROVIDER_CLASSES = {
      :ovirt      => 'Ovirt',
      :rhev       => 'Ovirt',
      :openstack  => 'OpenStack',
      :vsphere    => 'Vsphere',
      :vmware     => 'Vsphere',
      :baremetal  => 'BareMetal'
    }

    def self.load_provider(provider)
      require "#{PROVIDER_BASE}/#{PROVIDER_CLASSES[provider].downcase}"
      klass_name = "Dopv::Infrastructure::#{PROVIDER_CLASSES[provider]}"
      klass_name.split('::').inject(Object) { |res, i| res.const_get(i) }
    end

    def self.bootstrap_node(plan, state_store)
      provider = load_provider(plan.infrastructure.provider)
      provider.bootstrap_node(plan, state_store)
    end

    def self.destroy_node(plan, state_store, destroy_data_volumes=false)
      provider = load_provider(plan.infrastructure.provider)
      provider.destroy_node(plan, state_store, destroy_data_volumes)
    end

    def self.refresh_node(plan, state_store)
      provider = load_provider(plan.infrastructure.provider)
      provider.refresh_node(plan, state_store)
    end

  end
end
