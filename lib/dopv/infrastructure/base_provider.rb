require 'uri'
require 'fog'

module Dopv
  module Infrastructure
    KILO_BYTE = 1024
    MEGA_BYTE = 1024 * KILO_BYTE
    GIGA_BYTE = 1024 * MEGA_BYTE

    class ProviderError < StandardError; end

    class BaseProvider
      attr_reader :data_disks_db

      def self.bootstrap(node_config, data_disks_db)
        new(node_config, data_disks_db)
      end

      def initialize(node_config, data_disks_db)
        @compute_provider = nil
        @node_config = node_config
        @data_disks_db = data_disks_db
      end

      private

      def node_name
        @node_name ||= @node_config[:nodename]
      end

      def provider_username
        @provider_username ||= @node_config[:provider_username]
      end

      def provider_password
        @provider_password ||= @node_config[:provider_password]
      end

      def provider_url
        @provider_url ||= @node_config[:provider_endpoint]
      end

      def provider_scheme
        @provider_scheme ||= ::URI.parse(provider_url).scheme
      end

      def provider_host
        @provider_host ||= ::URI.parse(provider_url).host
      end

      def provider_port
        @provider_port ||= ::URI.parse(provider_url).port
      end

      def keep_ha?
        @keep_ha ||= @node_config[:keep_ha].nil? ? true : @node_config[:keep_ha]
      end

      def full_clone?
        @full_clone ||= @node_config[:full_clone].nil? ? true : @node_config[:full_clone]
      end

      def interfaces_config
        @interfaces_config ||= (@node_config[:interfaces] rescue [])
      end

      def affinities_config
        @affinities_config ||= (@node_config[:affinity_groups] rescue [])
      end

      def volumes_config
        @volumes_config ||= (@node_config[:disks] rescue [])
      end

      def compute_provider
        Dopv::log.info("Node #{node_name}: Creating compute provider.")
        @compute_provider ||= @compute_connection_opts ? ::Fog::Compute.new(@compute_connection_opts) : nil
      end

      def node_exist?
        begin
          compute_provider.servers.find { |node| node.name == node_name } ? true : false
        rescue => e
          raise ProviderError, "An error occured while searching node: #{e}"
        end
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
        @template ||= compute_provider.templates.all(filters).find { |t| t.name == @node_config[:image] }
        raise ProviderError, "No such template #{@node_config[:image]}" unless @template
        @template
      end

      def wait_for_task_completion(node_instance)
      end
      
      def node_instance_running?(node_instance)
      end

      def create_node_instance
        Dopv::log.info("Node #{node_name}: Creating node instance.")
        node_instance = compute_provider.servers.create(@node_creation_opts)
        wait_for_task_completion(node_instance)
        node_instance
      end

      def destroy_node_instance(node_instance, destroy_data_volumes=false)
        if node_instance
          stop_node_instance(node_instance)
          
          unless destroy_data_volumes
            data_volumes = data_disks_db.select { |v| disk.node == node_name }
            data_volumes.each do |v|
              ::Dopv::log.debug("Node #{vm.name} Detaching data volume #{v.name}.")
              detach_node_volume(node_instance, v) rescue nil
            end
          end

          ::Dopv::log.warn("Node #{node_name}: Destroying node.")
          node_instance.destroy
          wait_for_task_completion(node_instance)
        end
      end

      def customize_node_instance(node_instance)
      end

      def start_node_instance(node_instance)
      end

      def stop_node_instance
        if node_instance_running?(node_instance)
          node_instance.stop
          wait_for_task_completion(node_instance)
        end
      end

      def add_node_nic(node_instance, attrs)
        node_instance.interfaces.create(attrs)
        node_instance.interfaces.reload
      end

      def update_node_nic(node_instance, nic, attrs)
        nic.save(attrs)
        node_instance.interfaces.reload
      end

      def add_node_nics(node_instance)
      end

      def remove_node_nics(node_instance)
        Dopv::log.debug("Node #{node_name}: Removing interfaces defined by template.")
        node_instance.interfaces.each(&:destroy) rescue nil
        node_instance.interfaces.reload
      end
      
      def add_node_volume(node_instance, attrs)
        node_instance.volumes.create(attrs)
        wait_for_task_completion(node_instance)
      end

      def update_node_volume(node_instance, volume, attrs)
        node_instance.update_volume(attrs.merge(:id => volume.id))
        wait_for_task_completion(node_instance)
      end

      def attach_node_volume(node_instance, volume)
      end

      def detach_node_volume(node_instance, volume)
      end
      
      def add_node_data_volumes(node_instance)
        ::Dopv::log.info("Node #{node_name}: Adding data volumes.")

        ::Dopv::log.debug("Node #{node_name}: Loading data volumes DB.")
        data_volumes = data_disks_db.select { |dv| dv.node == node_name }

        # Check if persistent disks DB is consistent
        ::Dopv::log.debug("Node #{node_name}: Checking data volumes DB integrity.")
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
            err_msg = "Inconsistent disk DB: Disk #{cd[:name]} exists in plan but not in DB"
            raise ProviderError, err_msg
          end
        end

        # Attach all persistent disks
        data_volumes.each do |dv|
          ::Dopv::log.debug("Node #{node_name}: Attaching data volume #{dv.name} [#{dv.id}].")
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
          unless node_instance.volumes.find { |v| v == cv[:name] }
            ::Dopv::log.debug("Node #{node_name}: Creating disk #{cv[:name]} [#{cv[:size]}].")
            volume = add_node_volume(node_instance, cv)
            record_node_data_volume(volume)
          end
        end
      end
      
      def record_node_data_volume(volume)
        data_disks_db << volume.merge(:node => node_name)
        data_disks_db.save
      end

      def add_node_affinity(node_instance, name)
      end

      def add_node_affinities(node_instance)
        affinities_config.each do |a|
          ::Dopv::log.info("Node #{node_name}: Assigning affinity group #{a}.")
          add_node_affinity(node_instance, a)
        end
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
