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

        #vm = nil
        #cloud_init = {}

        #Dopv::log.info("Node #{node_config[:nodename]}: #{__method__}: Trying to deploy.")

        #cloud_init[:hostname] = node_config[:fqdn] ? node_config[:fqdn] : node_config[:nodename]
        #cloud_init[:dns] = (node_config[:dns][:nameserver] rescue nil)
        #cloud_init[:domain] = (node_config[:dns][:domain] rescue nil)

        #cloud_init[:user] = 'root'
        #cloud_init[:password] = (node_config[:credentials][:root_password] rescue nil)
        #cloud_init[:ssh_authorized_keys] = (node_config[:credentials][:root_ssh_keys] rescue nil)

        #nics = []
        #node_config[:interfaces].each do |nic_config|
        #  nic = {}
        #  if nic_config[:ip_address]
        #    nic[:nicname] = nic_config[:name]
        #    nic[:ip]      = nic_config[:ip_address]
        #    if nic_config[:ip_address] != 'dhcp'
        #      nic[:netmask] = nic_config[:ip_netmask]
        #      nic[:gateway] = nic_config[:ip_gateway] if nic_config[:set_gateway]
        #    end
        #  end
        #  nics << nic
        #end
        ## Current implementation of cloud-init in rbovirt does not support
        ## DHCP, nor multiple interfaces, hence the first interface for which
        ## a static IP is defined is passed.
        #cloud_init.merge!(nics[0]) if nics[0].is_a?(Hash)

        begin
          # Try to get the datacenter ID first.
          if node_exist?
            Dopv::log.warn("Node #{node_name}: Already exists, skipping.")
            return
          end

          node = create_node_instance
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
          raise Errors::ProviderError, "Node #{node_name}: #{e}"
        end
      end

      private

      def wait_for_task_completion(node_instance)
        node_instance.wait_for { !locked? }
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
          raise Errors::ProviderError, "Error while updating volume: #{e}"
        end

        node_instance
      end

      def destroy_node_instance(instance, data_disks_db)
        if vm
          ::Dopv::log.warn("Node #{vm.name}: #{__method__}: An error occured, rolling back.")
          vm.wait_for { !locked? }
          disks = data_disks_db.select {|disk| disk.node == vm.name}
          disks.each do |disk|
            ::Dopv::log.debug("Node #{vm.name}: #{__method__}: Trying to detach disk #{disk.name}.")
            vm.detach_volume(:id => disk.id) rescue nil
            vm.wait_for { !locked? }
          end
          ::Dopv::log.debug("Node #{vm.name}: #{__method__}: Destroying VM.")
          vm.destroy
        end
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
        raise Errors::ProviderError, "#{__method__} #{name}: No such affinity group" unless affinity_group
        node_instance.add_to_affinity_group(:id => affinity_group.id)
      end

      def add_node_volume(node_instance, attrs)
        storage_domain = compute_provider.storage_domains.find { |d| d.name == attrs[:pool] }
        raise Errors::ProviderError "No such storage domain #{attrs[:storage_domain]}" unless storage_domain

        attrs[:size] = get_size(attrs[:size])
        attrs[:storage_domain] = storage_domain.id

        volume = node_instance.add_volume(attrs.merge(:bootable => false, :wipe_after_delete => true))
        wait_for_task_completion(node_instance)
        volume
      end
      
      def attach_node_volume(node_instance, volume)
        node_instance.attach_volume(:id => volume.id)
        wait_for_task_completion(node_instance)
      end

      def detach_node_volume(node_instance, volume)
        node_instance.detach_volume(:id => volume.id)
        wait_for_task_completion(node_instance)
      end
      
      def record_node_volume(node_instance, volume)
        ::Dopv::log.debug("Node #{node_name}: Recording volume #{[:name]} into DB.")
        data_disks_db << {
          :node => node_name,
          :name => volume.alias,
          :id   => volume.id,
          :pool => volume.storage_domain,
          :size => volume.size
        }
        super
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
            raise Errors::ProviderError, err_msg
          end
        end
        volumes_config.each do |cv|
          # Disk exists in a plan but it is not recorded in the state DB for a
          # given node
          if !data_volumes.empty? && !data_volumes.find { |dv| cv[:name] == dv.name }
            err_msg = "Inconsistent disk DB: Disk #{cd[:name]} exists in plan but not in DB"
            raise Errors::ProviderError, err_msg
          end
        end

        # Attach all persistent disks
        data_volumes.each do |dv|
          ::Dopv::log.debug("Node #{node_name}: Attaching disk #{dv.name} [#{dv.id}].")
          attach_node_volume(node_instance, dv)
        end

        # Create those disks that do not exist in peristent disks DB and
        # record them into DB
        volumes_config.each do |cv|
          unless node_instance.volumes.find { |v| v == cv[:name] }
            ::Dopv::log.debug("Node #{node_name}: Creating disk #{cd[:name]} [#{cd[:size]}].")
            attrs = {
              :storage_domain => cv[:pool],
              :size => cv[:size],
              :alias => cd[:name]
            }
            volume = add_node_volume(node_instance, attrs)

            record_node_volume(node_instance, volume)
          end
        end
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
            raise Errors::ProviderError, "#{provider_url}: Cannot download CA certificate"
          end
        end
        local_ca_file
      end
    end
  end
end
