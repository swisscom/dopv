module Dopv
  module Infrastructure
    SUPPORTED_TYPES = {
      :ovirt      => 'ovirt',
      :rhev       => 'ovirt',
      :openstack  => 'openstack',
      :vsphere    => 'vsphere',
      :vmware     => 'vsphere'
    }

    TYPES_TO_CLASS_NAMES = {
      :ovirt      => 'Ovirt',
      :openstack  => 'OpenStack',
      :vsphere    => 'Vsphere'
    }
    
    def self.supported?(object)
      case object
      when String
        SUPPORTED_TYPES.has_key?(object.to_sym)
      when Symbol
        SUPPORTED_TYPES.has_key?(object)
      when Hash
        (SUPPORTED_TYPES.has_key?(object['type'].to_sym) || SUPPORTED_TYPES.has_key?(object[:type].to_sym)) rescue false
      else
        false
      end
    end

    def self.bootstrap(node)
      Object.const_get("Dopv::Infrastructure::#{TYPES_TO_CLASS_NAMES[node[:provider].to_sym]}::Node").bootstrap(node)
    end
  end
end
