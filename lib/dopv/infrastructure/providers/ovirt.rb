require 'fog'
require 'uri'
require 'open-uri'

module Dopv
  module Infrastructure
    module Ovirt
      class Node < BaseNode
        def initialize(node_config, disk_db)
          @compute_client = nil
          vm = nil
          cloud_init = {}
          
          Dopv::log.info("Provider: Ovirt: Node #{node_config[:nodename]}: #{__method__}: Trying to deploy.")

          cloud_init[:hostname] = node_config[:fqdn] ? node_config[:fqdn] : node_config[:nodename]

          cloud_init[:user] = 'root'
          cloud_init[:password] = (node_config[:credentials][:root_password] rescue nil)
          cloud_init[:ssh_authorized_keys] = (node_config[:credentials][:root_ssh_keys] rescue nil)

          node_config[:interfaces].each do |nic|
            if nic[:ip_address]
              cloud_init[:nicname] = nic[:name]
              cloud_init[:ip]      = nic[:ip_address]
              if nic[:ip_address] != 'dhcp'
                cloud_init[:netmask]  = nic[:ip_netmask]
                cloud_init[:gateway]  = nic[:ip_gateway]
              end
            end
          end
          
          begin
            # Try to get the datacenter ID first.
            @compute_client = create_compute_client(
              :username     => node_config[:provider_username],
              :password     => node_config[:provider_password],
              :endpoint     => node_config[:provider_endpoint],
              :datacenter   => node_config[:datacenter],
              :nodename     => node_config[:nodename]
            )

            if exist?(node_config[:nodename])
              Dopv::log.warn("Provider: Ovirt: Node #{node_config[:nodename]}: #{__method__}: Already exists, skipping.")
              return
            end

            # Create a VM
            vm = create_vm(node_config)

            # Add interfaces
            vm = add_interfaces(vm, node_config[:interfaces])

            # Add disks
            vm = add_disks(vm, node_config[:disks], disk_db)

            # Assign affinnity groups
            vm = assign_affinity_groups(vm, node_config[:affinity_groups])
            
            # Start a node with cloudinit
            vm.service.vm_start_with_cloudinit(:id => vm.id, :user_data => cloud_init)

            # Reload the node
            vm.reload
          rescue Exception => e
            destroy_vm(vm, disk_db)
            raise Errors::ProviderError, "Ovirt: Node #{node_config[:nodename]}: #{e}"
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
              raise Errors::ProviderError, "#{__method__} #{uri}: Cannot download CA certificate"
            ensure
              remote_ca.close if remote_ca
              local_ca.close if local_ca
            end
          end
          local_ca_file
        end

        def create_compute_client(attrs)
          Dopv::log.info("Provider: Ovirt: Node #{attrs[:nodename]}: #{__method__}: Creating compute client.")
          
          # Find the datacenter ID
          Dopv::log.debug("Provider: Ovirt: Node #{attrs[:nodename]}: #{__method__}: Getting data center ID.")
          compute_client = Fog::Compute.new(
              :provider           => 'ovirt',
              :ovirt_username     => attrs[:username],
              :ovirt_password     => attrs[:password],
              :ovirt_url          => attrs[:endpoint],
              :ovirt_ca_cert_file => get_endpoint_ca_cert(attrs[:endpoint])
          )
          datacenter = compute_client.datacenters.find { |dc| dc[:name] == attrs[:datacenter] }
          raise Errors::ProviderError, "#{__method__} #{attrs[:datacenter]}: No such data center" unless datacenter

          # Get a new compute client from a proper datacenter
          Dopv::log.debug("Provider: Ovirt: Node #{attrs[:nodename]}: #{__method__}: Recreating client with proper datacenter.")
          Fog::Compute.new(
              :provider           => 'ovirt',
              :ovirt_username     => attrs[:username],
              :ovirt_password     => attrs[:password],
              :ovirt_url          => attrs[:endpoint],
              :ovirt_ca_cert_file => get_endpoint_ca_cert(attrs[:endpoint]),
              :ovirt_datacenter   => datacenter[:id]
          )
        end

        def destroy_vm(vm, disk_db)
          if vm
            Dopv::log.warn("Provider: Ovirt: Node #{vm.name}: #{__method__}: An error occured, rolling back.")
            vm.wait_for { !locked? }
            disks = disk_db.find_all {|disk| disk.node == vm.name}
            disks.each do |disk|
              Dopv::log.debug("Provider: Ovirt: Node #{vm.name}: #{__method__}: Trying to detaching disk #{disk.name}.")
              vm.detach_volume(:id => disk.id) rescue nil
              vm.wait_for { !locked? }
            end
            Dopv::log.debug("Provider: Ovirt: Node #{vm.name}: #{__method__}: Destroying VM.")
            vm.destroy
          end
        end

        def create_vm(attrs)
          Dopv::log.info("Provider: Ovirt: Node #{attrs[:nodename]}: #{__method__}: Trying to create VM.")
          begin
            vm = @compute_client.servers.create(
              :name         => attrs[:nodename],
              :template     => get_template_id(attrs[:image]),
              :cores        => FLAVOR[attrs[:flavor].to_sym][:cores],
              :memory       => FLAVOR[attrs[:flavor].to_sym][:memory],
              :storage      => FLAVOR[attrs[:flavor].to_sym][:storage],
              :cluster      => get_cluster_id(attrs[:cluster]),
              :ha           => attrs[:keep_ha].nil? ? true: attrs[:keep_ha]
            )
            
            # Wait until all locks are released
            vm.wait_for { !locked? }
          rescue Exception => e
            raise Errors::ProviderError, "#{__method__}: #{e}"
          end
          vm
        end

        def get_storage_domain_id(storage_domain_name)
          storage_domain = @compute_client.storage_domains.find { |sd| sd.name == storage_domain_name}
          raise Errors::ProviderError, "#{__method__} #{storage_domain_name}: No such storage domain" unless storage_domain
          storage_domain.id
        end

        def get_volume_obj(volume_id)
          volume = @compute_client.volumes.find { |vol| vol.id == volume_id }
          raise Errors::ProviderError, "#{__method__} #{volume_id}: No such volume" unless volume
          volume
        end

        def get_affinity_group_id(affinity_group_name)
          affinity_group = @compute_client.affinity_groups.find {|ag| ag.name == affinity_group_name}
          raise Errors::ProviderError, "#{__method__} #{affinity_group_name}: No such affinity group" unless affinity_group
          affinity_group.id
        end
        
        def add_interfaces(vm, interfaces)
          Dopv::log.info("Provider: Ovirt: Node #{vm.name}: #{__method__}: Trying to add interfaces.")
          # Remove all interfaces defined by the template
          Dopv::log.debug("Provider: Ovirt: Node #{vm.name}: #{__method__}: Removing interfaces defined by template.")
          vm.interfaces.each do |nic|
            vm.destroy_interface(:id => nic.id)
            vm.wait_for { !locked? }
          end

          # Create network interfaces. In this step, interfaces are not assigned. This step
          # is used for MAC addresses reservation
          (1..interfaces.size).each do |idx|
            nicname = "tmp%d" % idx
            Dopv::log.debug("Provider: Ovirt: Node #{vm.name}: #{__method__}: Creating interface #{nicname}.")
            vm.add_interface(:name => nicname, :network_name => 'rhevm', :plugged => true, :linked => true)
            vm.wait_for { !locked? }
          end

          # Rearrange interfaces by their MAC addresses and assign them into
          # appropriate networks
          interfaces.reverse!
          vm.interfaces.reload.sort_by do |nic| nic.mac
            config = interfaces.pop
            Dopv::log.debug("Provider: Ovirt: Node #{vm.name}: #{__method__}: Configuring interface #{nic.name} (#{nic.mac}) as #{config[:name]} in #{config[:network]}.")
            vm.update_interface(:id => nic.id, :name => config[:name], :network_name => config[:network])
            vm.wait_for { !locked? }
          end

          # Explicitly reload nics & return VM
          vm.interfaces.reload
          vm
        end

        def assign_affinity_groups(vm, affinity_groups)
          Dopv::log.info("Provider: Ovirt: Node #{vm.name}: #{__method__}: Trying to assign affinity groups.")
          if affinity_groups
            affinity_groups.each do |ag_name|
              ag_id = get_affinity_group_id(ag_name)
              Dopv::log.debug("Provider: Ovirt: Node #{vm.name}: #{__method__}: Assigning affinity group #{ag_name}.")
              vm.add_to_affinity_group(:id => ag_id)
              vm.wait_for { !locked? }
            end
          end
          vm
        end

        def add_disks(vm, config_disks, disk_db)
          Dopv::log.info("Provider: Ovirt: Node #{vm.name}: #{__method__}: Trying to add disks.")
              
          Dopv::log.debug("Provider: Ovirt: Node #{vm.name}: #{__method__}: Loading persistent disks DB.")
          persistent_disks = disk_db.find_all {|pd| pd.node == vm.name}
          
          # Check if persistent disks DB is consistent
          Dopv::log.debug("Provider: Ovirt: Node #{vm.name}: #{__method__}: Checking DB integrity.")
          persistent_disks.each do |pd|
            # Disk exists in state DB but not in plan
            unless config_disks.find {|cd| pd.name == cd[:name]}
              err_msg = "#{__method__}: Inconsistent disk DB: Disk #{pd.name} exists in DB but not in plan"
              raise Errors::ProviderError, err_msg
            end
            # Disk exists in state DB but not on the server side
            unless @compute_client.volumes.find{|vol| pd.id == vol.id}
              err_msg = "#{__method__}: Inconsistent disk DB: Disk #{pd.name} does not exist on the server side"
              raise Errors::ProviderError, err_msg
            end
            # Disk exists in state DB as well as on server side, however storage
            # pools do not match,
            unless @compute_client.volumes.find{|vol| pd.id == vol.id && pd.pool == vol.storage_domain}
              err_msg = "#{__method__}: Inconsistent disk DB: Disk #{pd.name} is in a different storage pool on the server side"
              raise Errors::ProviderError, err_msg
            end
          end
          config_disks.each do |cd|
            # Disk exists in a plan but it is not recorded in the state DB for a
            # given node
            if !persistent_disks.empty? && !persistent_disks.find {|pd| cd[:name] == pd.name}
              err_msg = "#{__method__}: Inconsistent disk DB: Disk #{cd[:name]} exists in plan but not in DB"
              raise Errors::ProviderError, err_msg
            end
          end

          # Attach all persistent disks
          persistent_disks.each do |pd|
            Dopv::log.debug("Provider: Ovirt: Node #{vm.name}: #{__method__}: Attaching disk #{pd.name} [#{pd.id}].")
            vm.attach_volume(:id => pd.id)
            vm.wait_for { !locked? }
          end

          # Create those disks that do not exist in peristent disks DB and
          # record them into DB
          config_disks.each do |cd|
            unless vm.volumes.find {|vol| vol.alias == cd[:name]}
              Dopv::log.debug("Provider: Ovirt: Node #{vm.name}: #{__method__}: Creating disk #{cd[:name]} [#{cd[:size]}].")
              size = case cd[:size]
                     when /[1-9]*[Mm]/
                       (cd[:size].split(/[Mm]/)[0].to_f*1024*1024).to_i
                     when /[1-9]*[Gg]/
                       (cd[:size].split(/[Gg]/)[0].to_f*1024*1024*1024).to_i
                     when /[1-9]*[Tt]/
                       (cd[:size].split(/[Tt]/)[0].to_f*1024*1024*1024*1024).to_i
                     end
              storage_domain = get_storage_domain_id(cd[:pool])
              vm.add_volume( :storage_domain => storage_domain, :size => size, :bootable => 'false', :alias => cd[:name])
              vm.wait_for { !locked? }
              # Record volume to a persistent disks database
              Dopv::log.debug("Provider: Ovirt: Node #{vm.name}: #{__method__}: Recording disk #{cd[:name]} into DB.")
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
