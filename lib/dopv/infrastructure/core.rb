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

    # Based on http://docs.openstack.org/openstack-ops/content/flavors.html
    FLAVOR = {
      :tiny     => {
        :cores    => 1,
        :memory   => 536870912,
        :storage  => 1073741824
      },
      :small    => {
        :cores    => 1,
        :memory   => 2147483648,
        :storage  => 10737418240
      },
      :medium   => {
        :cores    => 2,
        :memory   => 4294967296,
        :storage  => 10737418240
      },
      :large    => {
        :cores    => 4,
        :memory   => 8589934592,
        :storage  => 10737418240
      },
      :xlarge   => {
        :cores    => 8,
        :memory   => 1744830464,
        :storage  => 10737418240
      }
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

    def self.bootstrap(node_config, disk_db)
      # Works only for Ruby 2.x and above
      #Object.const_get("Dopv::Infrastructure::#{TYPES_TO_CLASS_NAMES[node_config[:provider].to_sym]}::Node").bootstrap(node_config, disk_db)
      # Works also in Ruby 1.9x
      klass_name = "Dopv::Infrastructure::#{TYPES_TO_CLASS_NAMES[node_config[:provider].to_sym]}"
      klass = klass_name.split('::').inject(Object) {|res, i| res.const_get(i)}
      klass.bootstrap(node_config, disk_db)
    end
  end
end
