module Dopv
  module Cloud
    SUPPORTED_TYPES = {
      :ovirt     => 'ovirt',
      :rhev      => 'ovirt',
      :openstack => 'openstack',
      :vsphere   => 'vsphere',
      :vmware    => 'vsphere'
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

    def self.get_provider(clouds, name)
      SUPPORTED_TYPES[clouds[name]['type'].to_sym]
    end

    def self.get_username(clouds, name)
      clouds[name]['credentials']['username']
    end

    def self.get_password(clouds, name)
      clouds[name]['credentials']['username']
    end
    
    def self.get_url(clouds, name)
      clouds[name]['endpoint']
    end

  end
end
