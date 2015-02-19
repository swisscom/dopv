require 'fog'
require 'uri'
require 'open-uri'
require 'pry-debugger'

module Dopv
  module Infrastructure
    module Ovirt
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

      class Node < BaseNode
        def initialize(node_config, disk_db)
          @compute_client = nil
          vm = nil

          cloud_init = { :hostname => node_config[:nodename] }
          if node_config[:interfaces][0][:ip_address] != 'dhcp'
            cloud_init[:nicname]  = node_config[:interfaces][0][:name]
            cloud_init[:ip]       = node_config[:interfaces][0][:ip_address]
            cloud_init[:netmask]  = node_config[:interfaces][0][:ip_netmask]
            cloud_init[:gateway]  = node_config[:interfaces][0][:ip_gateway]
          end
          
          begin
            # Try to get the datacenter ID first.
            @compute_client = create_compute_client(
              :username     => node_config[:provider_username],
              :password     => node_config[:provider_password],
              :endpoint     => node_config[:provider_endpoint],
              :datacenter   => node_config[:datacenter]
            )

            # Create a VM
            vm = @compute_client.servers.create(
              :name     => node_config[:nodename],
              :template => get_template_id(node_config[:image]),
              :cores    => FLAVOR[node_config[:flavor].to_sym][:cores],
              :memory   => FLAVOR[node_config[:flavor].to_sym][:memory],
              :storage  => FLAVOR[node_config[:flavor].to_sym][:storage],
              :cluster  => get_cluster_id(node_config[:cluster])
            )

            # Wait until all locks are released
            vm.wait_for { !locked? }
            
            # Add interfaces
            vm = add_interfaces(vm, node_config[:interfaces])

            # Add disks
            vm = add_disks(vm, node_config[:disks], disk_db)
            
            # Start a node with cloudinit
            vm.service.vm_start_with_cloudinit(:id => vm.id, :user_data => cloud_init)

            # Reload the node
            vm.reload
          rescue Exception => e
            if vm
              vm.wait_for { !locked? }
              disks = disk_db.find_all {|disk| disk.node == vm.name}
              disks.each {|disk| vm.detach_volume(:id => disk.id)} rescue nil
              vm.destroy
            end
            raise Errors::ProviderError, "Error while creating '#{node_config[:nodename]}': #{e}"
          end
        end

        private

        def get_endpoint_ca_cert(url)
          uri = URI.parse(url)
          local_ca_file  = "/tmp/#{uri.hostname}_#{uri.port}_ca.crt"
          remote_ca_file = "#{uri.scheme}://#{uri.host}:#{uri.port}/ca.crt"
          local_ca = remote_ca = nil
          unless File.exists?(local_ca_file)
            begin
              remote_ca = open(remote_ca_file, :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE)
              local_ca  = open(local_ca_file, 'w')
              local_ca.write(remote_ca.read)
            rescue
              raise Errors::ProviderError, "Cannot download CA certificate from #{uri.host}"
            ensure
              remote_ca.close if remote_ca
              local_ca.close if local_ca
            end
          end
          local_ca_file
        end

        def create_compute_client(attrs)
          # Find the datacenter ID
          compute_client = Fog::Compute.new(
              :provider           => 'ovirt',
              :ovirt_username     => attrs[:username],
              :ovirt_password     => attrs[:password],
              :ovirt_url          => attrs[:endpoint],
              :ovirt_ca_cert_file => get_endpoint_ca_cert(attrs[:endpoint]),
              :ovirt_ca_no_verify => true
          )
          begin
            datacenter_id = compute_client.datacenters.find { |dc| dc[:name] == attrs[:datacenter] }[:id]
          rescue
            raise Errors::ProviderError, "No such datacenter '#{attrs[:datacenter]}'"
          end
          # Get a new compute client from a proper datacenter
          Fog::Compute.new(
              :provider           => 'ovirt',
              :ovirt_username     => attrs[:username],
              :ovirt_password     => attrs[:password],
              :ovirt_url          => attrs[:endpoint],
              :ovirt_ca_cert_file => get_endpoint_ca_cert(attrs[:endpoint]),
              :ovirt_ca_no_verify => true,
              :ovirt_datacenter   => datacenter_id
          )
        end

        def get_cluster_id(cluster_name)
          begin
            @compute_client.list_clusters.find { |cl| cl[:name] == cluster_name }[:id]
          rescue
            raise Errors::ProviderError, "No such cluster '#{cluster_name}'"
          end
        end

        def get_template_id(template_name)
          begin
            @compute_client.list_templates.find { |tpl| tpl[:name] == template_name }[:id]
          rescue
            raise Errors::ProviderError, "No such template '#{template_name}'"
          end
        end
        
        def get_storage_domain_id(storage_domain_name)
          begin
            @compute_client.storage_domains.find { |sd| sd.name == storage_domain_name}.id
          rescue
            raise Errors::ProviderError, "No such storage domain '#{storage_domain_name}'"
          end
        end

        def get_volume_obj(volume_id)
          begin
            @compute_client.volumes.find { |vol| vol.id == volume_id }
          rescue
            raise Errors::ProviderError, "No such volume with id '#{volume_id}'"
          end
        end
        
        def add_interfaces(vm, interfaces)
          # Remove all interfaces defined by the template
          vm.interfaces.each { |interface| vm.destroy_interface(:id => interface.id) }
          # Create all interfaces defined in node configuration
          interfaces.each do |interface|
            begin
              network = @compute_client.list_networks(vm.cluster).find { |n| n.name == interface[:network] }
            rescue
              raise Errors::ProviderError, "Cannot create interface, no such network '#{interface[:network]}'"
            end
            vm.add_interface(
              :network  => network.id,
              :name     => interface[:name],
              :plugged  => true,
              :linked   => true,
            )
            vm.wait_for { !locked? }
            vm = vm.save
          end
          vm
        end

        def assign_affinity_groups(affinity_groups)
          # Until merged to upstream
          # https://github.com/abenari/rbovirt/issues/67
          require 'ext/rbovirt/ovirt/affinity_group'
          require 'ext/rbovirt/client/affinity_group_api'
        end

        def add_disks(vm, config_disks, disk_db)
          # Until merged to upstream
          # https://github.com/abenari/rbovirt/pull/66
          require 'ext/rbovirt/ovirt/volume'
          # https://github.com/abenari/rbovirt/issues/67
          require 'ext/fog/ovirt/compute'
          require 'ext/fog/ovirt/models/compute/server'
          require 'ext/fog/ovirt/models/compute/volumes'
          require 'ext/fog/ovirt/models/compute/volume'
          require 'ext/fog/ovirt/requests/compute/attach_volume'
          require 'ext/fog/ovirt/requests/compute/detach_volume'
          require 'ext/fog/ovirt/requests/compute/list_volumes'

          persistent_disks = disk_db.find_all {|pd| pd.node == vm.name}
          
          # Check if persistent disks DB is consistent
          persistent_disks.each do |pd|
            # Disk exists in state DB but not in plan
            unless config_disks.find {|cd| pd.name == cd[:name]}
              err_msg = "Inconsistent disk DB: disk '#{pd.name}' exists in DB but not in plan"
              raise Errors::ProviderError, err_msg
            end
            # Disk exists in state DB but not on the server side
            unless @compute_client.volumes.find{|vol| pd.id == vol.id}
              err_msg = "Inconsistent disk DB: disk '#{pd.name}' does not exist on the server side"
              raise Errors::ProviderError, err_msg
            end
            # Disk exists in state DB as well as on server side, however storage
            # pools do not match,
            unless @compute_client.volumes.find{|vol| pd.id == vol.id && pd.pool == vol.storage_domain}
              err_msg = "Inconsistent disk DB: disk '#{pd.name}' is in a different storage pool on the server side"
              raise Errors::ProviderError, err_msg
            end
          end
          config_disks.each do |cd|
            # Disk exists in a plan but it is not recorded in the state DB for a
            # given node
            if !persistent_disks.empty? && !persistent_disks.find {|pd| cd[:name] == pd.name}
              err_msg = "Inconsistent disk DB: disk '#{cd[:name]}' exists in plan but not in DB"
              raise Errors::ProviderError, err_msg
            end
          end

          # Attach all persistent disks
          persistent_disks.each do |pd|
            vm.attach_volume(:id => pd.id)
            vm.wait_for { !locked? }
            vm = vm.save
          end

          # Create those disks that do not exist in peristent disks DB and
          # record them into DB
          config_disks.each do |cd|
            unless vm.volumes.find {|vol| vol.alias == cd[:name]}
              size = case cd[:size]
                     when /[1-9]*[Mm]/
                       (cd[:size].split(/[Mm]/)[0].to_f*1024*1024).to_i
                     when /[1-9]*[Gg]/
                       (cd[:size].split(/[Gg]/)[0].to_f*1024*1024*1024).to_i
                     when /[1-9]*[Tt]/
                       (cd[:size].split(/[Tt]/)[0].to_f*1024*1024*1024*1024).to_i
                     end
              storage_domain = get_storage_domain_id(cd[:pool])
              vm.add_volume(
                :storage_domain => storage_domain,
                :size           => size,
                :bootable       => 'false',
                :alias          => cd[:name]
              )
              # Wait until all locks are released and re-save the VM state 
              vm.wait_for { !locked? }
              vm = vm.save
              # Record volume to a persistent disks database
              disk = vm.volumes.find {|vol| vol.alias == cd[:name]}
              disk_db << {
                :node => vm.name,
                :name => disk.alias,
                :id   => disk.id,
                :pool => disk.storage_domain,
                :size => disk.size
              }
            end
          end
          vm
        end
      end
    end
  end
end
