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

    def self.supported_provider?(object)
      case object
      when String
        PROVIDER_CLASSES.has_key?(object.to_sym)
      when Symbol
        PROVIDER_CLASSES.has_key?(object)
      when Hash
        (PROVIDER_CLASSES.has_key?(object['type'].to_sym) || PROVIDER_CLASSES.has_key?(object[:type].to_sym)) rescue false
      else
        false
      end
    end

    def self.provider_module(provider_name)
      "#{PROVIDER_BASE}/#{PROVIDER_CLASSES[provider_name.to_sym].downcase}"
    end

    def self.provider_class(provider_name)
      klass_name = "Dopv::Infrastructure::#{PROVIDER_CLASSES[provider_name.to_sym.downcase]}"
      klass_name.split('::').inject(Object) { |res, i| res.const_get(i) }
    end

    def self.load_provider(provider_name)
      raise ProviderError, "Unsupported provider #{provider_name.to_s}" unless supported_provider?(provider_name)
      require provider_module(provider_name)
      klass = provider_class(provider_name)
    end

    def self.bootstrap_node(node_config, data_disk_db)
      provider = load_provider(node_config[:provider])
      provider.bootstrap_node(node_config, data_disk_db)
    end

    def self.destroy_node(node_config, data_disk_db, destroy_data_volumes=false)
      provider = load_provider(node_config[:provider])
      provider.destroy_node(node_config, data_disk_db, destroy_data_volumes)
    end
  end
end
