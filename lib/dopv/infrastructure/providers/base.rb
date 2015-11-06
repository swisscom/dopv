require 'uri'
require 'fog'

module Dopv
  module Infrastructure
    class ProviderError < StandardError
      def exit_code; 4; end
    end

    class Base
      KILO_BYTE = 1024
      MEGA_BYTE = 1024 * KILO_BYTE
      GIGA_BYTE = 1024 * MEGA_BYTE

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
          :memory   => 17179869184,
          :storage  => 10737418240
        }
      }

      attr_reader :data_disks_db

      def self.bootstrap_node(node_config, data_disks_db)
        new(node_config, data_disks_db).bootstrap_node
      end

      def self.destroy_node(node_config, data_disks_db, destroy_data_volumes=false)
        new(node_config, data_disks_db).destroy_node(destroy_data_volumes)
      end

      def initialize(node_config, data_disks_db)
        @compute_provider = nil
        @node_config = node_config
        @data_disks_db = data_disks_db
      end

      def bootstrap_node
        begin
          unless node_exist?
            node_instance = create_node_instance
            add_node_nics(node_instance)
            add_node_data_volumes(node_instance)
            add_node_affinities(node_instance)
            start_node_instance(node_instance)
          else
            ::Dopv::log.warn("Node #{nodename}: Already exists.")
          end
        rescue Exception => e
          ::Dopv::log.error("Node #{nodename}: #{e}")
          destroy_node_instance(node_instance)
          raise ProviderError, "Node #{nodename}: #{e}."
        end
      end

      def destroy_node(destroy_data_volumes=false)
        if node_exist?
          node_instance = compute_provider.servers.find { |n| n.name == nodename }
          destroy_node_instance(node_instance, destroy_data_volumes)
        end
      end

      private

      def nodename
        @node_config[:nodename]
      end

      def fqdn
        @node_config[:fqdn] || nodename
      end

      def hostname
        fqdn.split(".").first
      end

      def domainname
        fqdn.split(".").drop(1).join(".")
      end

      def provider_username
        @node_config[:provider_username]
      end

      def provider_password
        @node_config[:provider_password]
      end

      def provider_url
        @node_config[:provider_endpoint]
      end

      def provider_scheme
        ::URI.parse(provider_url).scheme
      end

      def provider_host
        ::URI.parse(provider_url).host
      end

      def provider_port
        ::URI.parse(provider_url).port
      end

      def keep_ha?
        @node_config[:keep_ha].nil? ? true : @node_config[:keep_ha]
      end

      def full_clone?
        @node_config[:full_clone].nil? ? true : @node_config[:full_clone]
      end

      def thin_provisioned?(volume_config)
        volume_config[:thin].nil? ? true : volume_config[:thin]
      end

      def default_pool
        @node_config[:default_pool]
      end

      def interfaces_config
        @node_config[:interfaces] || []
      end

      def set_gateway?(interface_config)
        interface_config[:set_gateway].nil? ? true : interface_config[:set_gateway]
      end

      def affinities_config
        @node_config[:affinity_groups] || []
      end

      def volumes_config
        @node_config[:disks] || []
      end

      def ns_config
        @node_config[:dns] || {}
      end

      def nameservers
        ns_config[:nameserver] rescue nil
      end

      def searchdomains
        ns_config[:domain] rescue nil
      end

      def timezone
        @node_config[:timezone]
      end

      def credentials_config
        @node_config[:credentials]
      end

      def root_password
        credentials_config[:root_password] rescue nil
      end

      def root_ssh_keys
       credentials_config[:root_ssh_keys] rescue nil
      end

      def administrator_password
        credentials_config[:administrator_password] rescue nil
      end

      def administrator_fullname
        credentials_config[:administrator_fullname] rescue 'Administrator'
      end

      def compute_provider
        Dopv::log.info("Node #{nodename}: Creating compute provider.") unless @compute_provider
        @compute_provider ||= @compute_connection_opts ? ::Fog::Compute.new(@compute_connection_opts) : nil
      end

      def datacenter(filters={})
       @datacenter ||= compute_provider.datacenters(filters).find do |d|
          if d.is_a?(Hash) && d.has_key?(:name)
            d[:name] == @node_config[:datacenter]
          elsif d.methods.include?(:name)
            d.name == @node_config[:datacenter]
          else
            raise ProviderError, "Unsupported datacenter class #{d.class}"
          end
        end
        raise ProviderError, "No such data center #{@node_config[:datacenter]}" unless @datacenter
        @datacenter
      end

      def cluster(filters={})
        @cluster ||= compute_provider.clusters(filters).find { |c| c.name == @node_config[:cluster] }
        raise ProviderError, "No such cluster #{@node_config[:cluster]}" unless @cluster
        @cluster
      end

      def template(filters={})
        raise ProviderError, "No template defined" unless @node_config[:image]
        @template ||= if compute_provider.respond_to?(:templates)
                         compute_provider.templates.all(filters).find { |t| t.name == @node_config[:image] }
                       elsif compute_provider.respond_to?(:images)
                         compute_provider.images.all(filters).find { |t| t.name == @node_config[:image] }
                       else
                         raise ProviderError, "The provider does not to have template/image collection"
                       end
        raise ProviderError, "No such template #{@node_config[:image]}" unless @template
        @template
      end

      def node_exist?
        begin
          if compute_provider.servers.find { |n| n.name == nodename }
            return true
          end
        rescue => e
          raise ProviderError, "An error occured while searching for a node: #{e}"
        end

        false
      end

      def node_instance_ready?(node_instance)
        node_instance.ready?
      end

      def node_instance_stopped?(node_instance)
        node_instance.stopped?
      end

      def wait_for_task_completion(node_instance)
      end

      def create_node_instance
        Dopv::log.info("Node #{nodename}: Creating node instance.")
        node_instance = compute_provider.servers.create(@node_creation_opts)
        wait_for_task_completion(node_instance)
        node_instance
      end

      def destroy_node_instance(node_instance, destroy_data_volumes=false)
        if node_instance
          stop_node_instance(node_instance)

          volumes = data_disks_db.select { |v| v.node == nodename }
          volumes.each do |v|
            if destroy_data_volumes
              ::Dopv::log.warn("Node #{nodename} Destroying data volume #{v.name}.")
              begin
                destroy_node_volume(node_instance, v)
              rescue
                ::Dopv::log.error("Could not destroy data volume #{v.name}. Please fix manually.")
              end
              erase_node_data_volume(v)
            else
              ::Dopv::log.debug("Node #{nodename} Detaching data volume #{v.name}.")
              begin
                detach_node_volume(node_instance, v)
              rescue
                ::Dopv::log.warn("Could not detach data volume #{v.name}.")
              end
            end
          end

          ::Dopv::log.warn("Node #{nodename}: Destroying node.")
          node_instance.destroy rescue nil
        end
      end

      def reload_node_instance(node_instance)
        node_instance.reload
      end

      def customize_node_instance(node_instance)
      end

      def start_node_instance(node_instance)
        stop_node_instance(node_instance)
        ::Dopv::log.info("Node #{nodename}: Starting node.")
        customize_node_instance(node_instance)
      end

      def stop_node_instance(node_instance)
        reload_node_instance(node_instance)
        unless node_instance_stopped?(node_instance)
          ::Dopv::log.info("Node #{nodename}: Stopping node.")
          wait_for_task_completion(node_instance)
          node_instance.stop
          reload_node_instance(node_instance)
        end
      end

      def add_node_nic(node_instance, attrs)
        nic = node_instance.interfaces.create(attrs)
        node_instance.interfaces.reload
        nic
      end

      def update_node_nic(node_instance, nic, attrs)
        nic.save(attrs)
        node_instance.interfaces.reload
      end

      def add_node_nics(node_instance)
      end

      def remove_node_nics(node_instance)
        Dopv::log.debug("Node #{nodename}: Removing (possible) network interfaces defined by template.")
        if block_given?
          node_instance.interfaces.each { |nic| yield(node_instance, nic) }
        else
          node_instance.interfaces.each(&:destroy) rescue nil
        end
        node_instance.interfaces.reload
      end

      def add_node_affinity(node_instance, affinity)
      end

      def remove_node_affinity(node_instance, affinity)
      end

      def add_node_volume(node_instance, attrs)
        node_instance.volumes.create(attrs)
      end

      def update_node_volume(node_instance, volume, attrs)
        node_instance.update_volume(attrs.merge(:id => volume.id))
        wait_for_task_completion(node_instance)
        node_instance.volumes.reload
        volume
      end

      def destroy_node_volume(node_instance, volume)
      end

      def attach_node_volume(node_instance, volume)
      end

      def detach_node_volume(node_instance, volume)
      end

      def add_node_data_volumes(node_instance)
        ::Dopv::log.info("Node #{nodename}: Adding data volumes.")

        ::Dopv::log.debug("Node #{nodename}: Loading data volumes DB.")
        data_volumes = data_disks_db.select { |dv| dv.node == nodename }

        # Check if persistent disks DB is consistent
        ::Dopv::log.debug("Node #{nodename}: Checking data volumes DB integrity.")
        data_volumes.each do |dv|
          # Disk exists in state DB but not in plan
          unless volumes_config.find { |cv| dv.name == cv[:name] }
            err_msg = "Inconsistent data volumes DB: Volume #{dv.name} exists in DB but not in plan"
            raise ProviderError, err_msg
          end
        end
        volumes_config.each do |cv|
          # Disk exists in a plan but it is not recorded in the state DB for a
          # given node
          if !data_volumes.empty? && !data_volumes.find { |dv| cv[:name] == dv.name }
            ::Dopv::log.warn("Node #{nodename}: Data volume #{cv[:name]} exists in plan but not in DB.")
          end
        end

        # Attach all persistent disks
        data_volumes.each do |dv|
          ::Dopv::log.debug("Node #{nodename}: Attaching data volume #{dv.name} [#{dv.id}].")
          begin
            attach_node_volume(node_instance, dv)
          rescue Exception => e
            err_msg = "An error occured while attaching data volume #{dv.name}: #{e}"
            raise ProviderError, err_msg
          end
        end

        # Create those disks that do not exist in peristent disks DB and
        # record them into DB
        volumes_config.each do |cv|
          unless data_disks_db.find { |v| v.name == cv[:name] }
            ::Dopv::log.debug("Node #{nodename}: Creating disk #{cv[:name]} [#{cv[:size]}].")
            volume = add_node_volume(node_instance, cv)
            record_node_data_volume(volume)
          end
        end
      end

      def record_node_data_volume(volume)
        ::Dopv::log.debug("Node #{nodename} Recording data volume #{volume[:name]} from data volumes DB.")
        data_disks_db << volume.merge(:node => nodename)
        data_disks_db.save
      end

      def erase_node_data_volume(volume)
        ::Dopv::log.debug("Node #{nodename} Erasing data volume #{volume.name} from data volumes DB.")
        data_disks_db.delete(volume)
        data_disks_db.save
      end

      def add_node_affinity(node_instance, name)
      end

      def add_node_affinities(node_instance)
        affinities_config.each { |a| add_node_affinity(node_instance, a) }
      end

      def get_size(value, return_unit=:byte)
        size_in_bytes = case value
                        when /\d[Mm]/
                          value.split(/[Mm]/).first.to_i * MEGA_BYTE
                        when /\d[Gg]/
                          value.split(/[Mm]/).first.to_i * GIGA_BYTE
                        else
                          value.to_i rescue 0
                        end
        raise ProviderError, "Invalid value #{value}" unless  size_in_bytes > 0

        case return_unit
        when :gigabyte
          (size_in_bytes / GIGA_BYTE).to_i
        when :megabyte
          (size_in_bytes / MEGA_BYTE).to_i
        when :kilobyte
          (size_in_bytes / KILO_BYTE).to_i
        when :byte
          size_in_bytes
        else
          raise ProviderError, "Invalid return unit value #{return_unit}"
        end
      end

      def cores
        unless @cores
          value = case @node_config[:flavor]
                  when nil
                    case @node_config[:cores]
                    when Integer
                      @node_config[:cores]
                    when /\d/
                      @node_config[:cores].to_i
                    else
                      FLAVOR[:medium][:cores]
                    end
                  else
                    FLAVOR[@node_config[:flavor].to_sym][:cores] rescue 0
                  end
          @cores = value
        end
        raise ProviderError, "Invalid cores value #{value}" unless @cores > 0
        @cores
      end

      def memory(return_unit=:byte)
        unless @memory
          value = @node_config[:flavor] ?
            (FLAVOR[@node_config[:flavor].to_sym][:memory] rescue nil) :
            (@node_config[:memory].nil? ? FLAVOR[:medium][:memory] : @node_config[:memory])
          @memory = get_size(value, return_unit)
        end
        @memory
      end

      def storage(return_unit=:byte)
        unless @storage
          value = @node_config[:flavor] ?
            (FLAVOR[@node_config[:flavor].to_sym][:storage] rescue nil) :
            (@node_config[:storage].nil? ? FLAVOR[:medium][:storage] : @node_config[:storage])
          @storage = get_size(value, return_unit)
        end
        @storage
      end
    end
  end
end
