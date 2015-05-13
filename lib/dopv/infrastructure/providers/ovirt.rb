require 'fog'
require 'uri'
require 'open-uri'

module Dopv
  module Infrastructure
    class Ovirt < BaseProvider
      def initialize(node_config, data_disks_db)
        super(node_config, data_disks_db)
        
        @compute_connection_opts = {
          :provider           => 'ovirt',
          :ovirt_username     => provider_username,
          :ovirt_password     => provider_password,
          :ovirt_url          => provider_url,
          :ovirt_ca_cert_file => provider_ca_cert_file
        }

        @node_creation_opts = {
          :name       => node_name,
          :template   => template.id,
          :cores      => cores,
          :memory     => memory,
          :storage    => storage,
          :cluster    => cluster.id,
          :ha         => keep_ha?,
          :clone      => full_clone?
        }

        #Dopv::log.info("Node #{node_config[:nodename]}: #{__method__}: Trying to deploy.")


        begin
          # Try to get the datacenter ID first.
          #if node_exist?
          #  Dopv::log.warn("Node #{node_name}: Already exists, skipping.")
          #  return
          #end

          node = compute_provider.servers.find { |s| s.name == node_name }
          
          #node = create_node_instance
          binding.pry

          # Add interfaces
          #vm = add_interfaces(vm, node_config[:interfaces])

          # Add disks
          #vm = add_disks(vm, node_config[:disks], data_disks_db)

          # Assign affinnity groups
          #vm = assign_affinity_groups(vm, node_config[:affinity_groups])

          # Start a node with cloudinit
          #vm.service.vm_start_with_cloudinit(:id => vm.id, :user_data => cloud_init)

          # Reload the node
          #vm.reload
        rescue Exception => e
          #destroy_vm(vm, data_disks_db)
          raise ProviderError, "Node #{node_name}: #{e}."
        end
      end

      private

      def wait_for_task_completion(node_instance)
        node_instance.wait_for { !locked? }
      end
      
      def node_instance_running?(node_instance)
        !node_instance.stopped?
      end

      def compute_provider
        unless @compute_provider
          super
          ::Dopv::log.debug("Node #{node_name}: Recreating client with proper datacenter.")
          @compute_connection_opts[:ovirt_datacenter] = datacenter[:id]
          @compute_provider = ::Fog::Compute.new(@compute_connection_opts)
        end
        @compute_provider
      end

      def create_node_instance
        begin
          # Create node instance
          node_instance = super

          # For each disk, set up wipe after delete flag
          node_instance.volumes.each do |v|
            ::Dopv::log.debug("Node #{node_name}: Setting wipe after delete for disk #{v.alias}.")
            update_node_volume(node_instance, v, {:wipe_after_delete => true})
          end
        rescue Exception => e
          raise ProviderError, "Error while updating volume: #{e}"
        end

        node_instance
      end

      def customize_node_instance(node_instance)
        customization_opts = {
          :hostname => node_config[:fqdn] ? node_config[:fqdn] : node_name,
          :dns => (node_config[:dns][:nameserver] rescue nil),
          :domain => (node_config[:dns][:domain] rescue nil),
          :user => 'root',
          :password => (node_config[:credentials][:root_password] rescue nil)
          :ssh_authorized_keys => (node_config[:credentials][:root_ssh_keys] rescue nil)
        }

        nics = []
        node_config[:interfaces].each do |nc|
          nic = {}
          if nc[:ip_address]
            nic[:nicname] = nc[:name]
            nic[:ip] = nc[:ip_address]
            if nc[:ip_address] != 'dhcp' && nc[:ip_address] != 'none'
              nic[:netmask] = nc[:ip_netmask]
              nic[:gateway] = nc[:ip_gateway] if nc[:set_gateway]
            end
          end
          nics << nic
        end
        # Current implementation of cloud-init in rbovirt does not support
        # DHCP/NONE, nor multiple interfaces, hence the first interface for
        # which a static IP is defined is passed.
        customization_opts.merge!(nics.first) if nics.first.is_a?(Hash)
        
        customization_opts
      end

      def start_node_instance(node_instance)
        customization_opts = customize_node_instance(node_instance)
        node_instance.service.vm_start_with_cloudinit(
          :id => node_instance.id,
          :user_data => customization_opts
        )
      end

      def add_node_nic(node_instance, attrs)
        node_instance.add_interface(attrs)
        node_instance.interfaces.reload
      end

      def update_node_nic(node_instance, nic, attrs)
        node_instance.update_interface(attrs.merge({:id => nic.id}))
        wait_for_task_completion(node_instance)
      end

      def add_node_nics(node_instance)
        ::Dopv::log.info("Node #{node_name}: Trying to add interfaces.")
        
        # Remove all interfaces defined by the template
        remove_node_nics(node_instance)

        # Create network interfaces. In this step, interfaces are not assigned. This step
        # is used for MAC addresses reservation
        (1..interfaces_config.size).each do |i|
          name = "tmp#{i}"
          ::Dopv::log.debug("Node #{node_name}: Creating interface #{name}.")
          attrs = {
            :name => name,
            :network_name => 'rhevm',
            :plugged => true,
            :linked => true
          }
          add_node_nic(node_instance, attrs)
        end

        # Rearrange interfaces by their MAC addresses and assign them into
        # appropriate networks
        interfaces_config.reverse!
        node_instance.interfaces.sort_by do |n| n.mac
          cfg = interfaces_config.pop
          ::Dopv::log.debug("Node #{node_name}: Configuring interface #{n.name} (#{n.mac}) as #{cfg[:name]} in #{cfg[:network]}.")
          attrs = {
            :name => cfg[:name],
            :network_name => cfg[:network],
          }
          update_node_nic(node_instance, n, attrs)
        end
      end

      def remove_node_nics(node_instance)
        ::Dopv::log.debug("Node #{node_name}: Removing interfaces defined by template.")
        node_instance.interfaces.each { |i| node_instance.destroy_interface(:id => i.id) } rescue nil
        node_instance.interfaces.reload
      end

      def add_node_affinity(node_instance, name)
        affinity_group = compute_provider.affinity_groups.find { |g| g.name == name }
        raise ProviderError, "No such affinity group #{name}" unless affinity_group
        node_instance.add_to_affinity_group(:id => affinity_group.id)
      end

      def add_node_volume(node_instance, attrs)
        storage_domain = compute_provider.storage_domains.find { |d| d.name == attrs[:pool] }
        raise ProviderError, "No such storage domain #{attrs[:storage_domain]}" unless storage_domain

        attrs[:alias] = attrs[:name]
        attrs[:size] = get_size(attrs[:size])
        attrs[:storage_domain] = storage_domain.id
        attrs.delete_if { |k,v| k == :name || k == :pool }

        node_instance.add_volume(attrs.merge(:bootable => 'false', :wipe_after_delete => 'true'))
        wait_for_task_completion(node_instance)
        node_instance.volumes.find { |v| v.alias == attrs[:alias] }
      end
      
      def attach_node_volume(node_instance, volume)
        node_instance.attach_volume(:id => volume.id)
        wait_for_task_completion(node_instance)
      end

      def detach_node_volume(node_instance, volume)
        node_instance.detach_volume(:id => volume.id)
        wait_for_task_completion(node_instance)
      end
      
      def record_node_volume(volume)
        ::Dopv::log.debug("Node #{node_name}: Recording volume #{[:name]} into DB.")
        volume = {
          :name => volume.alias,
          :id   => volume.id,
          :pool => volume.storage_domain,
          :size => volume.size
        }
        super(volume)
      end

      def provider_ca_cert_file
        local_ca_file = "#{TMP}/#{provider_host}_#{provider_port}_ca.crt"
        remote_ca_file = "#{provider_scheme}://#{provider_host}:#{provider_port}/ca.crt"
        unless File.exists?(local_ca_file)
          begin
            open(remote_ca_file, :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE) do |remote_ca|
              local_ca = open(local_ca_file, 'w')
              local_ca.write(remote_ca.read)
              local_ca.close
            end
          rescue
            raise ProviderError, "Cannot download CA certificate from #{provider_url}"
          end
        end
        local_ca_file
      end
    end
  end
end
