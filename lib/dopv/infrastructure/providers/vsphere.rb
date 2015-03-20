require 'fog'
require 'uri'
require 'pry-debugger'

module Dopv
  module Infrastructure
    module Vsphere
      # Based on
      # http://pubs.vmware.com/vsphere-50/index.jsp?topic=/com.vmware.wssdk.apiref.doc_50/vim.vm.GuestOsDescriptor.GuestOsIdentifier.html
      GUEST_ID_TO_OS_FAMILY = {
        :debian6_64Guest        => :linux,
        :debian6_Guest          => :linux,
        :rhel4_64Guest          => :linux,
        :rhel4Guest             => :linux,
        :rhel5_64Guest          => :linux,
        :rhel5Guest             => :linux,
        :rhel6_64Guest          => :linux,
        :rhel6Guest             => :linux,
        :rhel7_64Guest          => :linux,
        :rhel7Guest             => :linux,
        :oracleLinux64Guest     => :linux,
        :oracleLinuxGuest       => :linux,
        :ubuntu64Guest          => :linux,
        :ubuntuGuest            => :linux,
        :windows7_64Guest       => :windows,
        :windows7Guest          => :windows,
        :windows7Server64Guest  => :windows,
        :windows8_64Guest       => :windows,
        :windows8Guest          => :windows,
        :windows8Server64Guest  => :windows
      }

      class Node < BaseNode
        def initialize(node_config, disk_db)
          @compute_client = nil
          vm = nil
          
          Dopv::log.info("Provider: Vsphere: Node #{node_config[:nodename]}: #{__method__}: Trying to deploy.")

          begin
            # Try to get the datacenter ID first.
            @compute_client = create_compute_client(
              :username     => node_config[:provider_username],
              :password     => node_config[:provider_password],
              :apikey       => node_config[:provider_apikey],
              :endpoint     => node_config[:provider_endpoint],
              :datacenter   => node_config[:datacenter],
              :nodename     => node_config[:nodename]
            )

            if exist?(node_config[:nodename])
              Dopv::log.warn("Provider: Vsphere: Node #{node_config[:nodename]}: #{__method__}: Already exists, skipping.")
              return
            end

            # Create a VM
            vm = create_vm(node_config)

            # Add interfaces
            #vm = @compute_client.servers.find {|srv| srv.name == node_config[:nodename]}
            vm = add_interfaces(vm, node_config[:interfaces])

            # Add disks
            #vm = add_disks(vm, node_config[:disks], disk_db)

            # Assign affinnity groups
            #vm = assign_affinity_groups(vm, node_config[:affinity_groups])

            # Start a node with cloudinit
            #vm.service.vm_start_with_cloudinit(:id => vm.id, :user_data => cloud_init)

            # Reload the node
            vm.reload
          rescue Exception => e
            destroy_vm(vm, disk_db)
            raise Errors::ProviderError, "Vsphere: Node #{node_config[:nodename]}: #{e}"
          end
        end

        private

        def create_compute_client(attrs)
          Dopv::log.info("Provider: Vsphere: Node #{attrs[:nodename]}: #{__method__}: Creating compute client.")
          uri = URI.parse(attrs[:endpoint])

          compute_client = Fog::Compute.new(
              :provider                     => 'vsphere',
              :vsphere_username             => attrs[:username],
              :vsphere_password             => attrs[:password],
              :vsphere_server               => uri.host,
              :vsphere_port                 => uri.port,
              :vsphere_expected_pubkey_hash => attrs[:apikey]
          )
          compute_client
        end

        def destroy_vm(vm, disk_db)
          if vm
            Dopv::log.warn("Provider: Vsphere: Node #{vm.name}: #{__method__}: An error occured, rolling back.")
            vm.wait_for { !locked? }
            disks = disk_db.find_all {|disk| disk.node == vm.name}
            disks.each do |disk|
              Dopv::log.debug("Provider: Vsphere: Node #{vm.name}: #{__method__}: Trying to detaching disk #{disk.name}.")
              vm.detach_volume(:id => disk.id) rescue nil
              vm.wait_for { !locked? }
            end
            Dopv::log.debug("Provider: Vsphere: Node #{vm.name}: #{__method__}: Destroying VM.")
            vm.destroy
          end
        end

        def create_vm(attrs)
          Dopv::log.info("Provider: Vsphere: Node #{attrs[:nodename]}: #{__method__}: Trying to create VM.")

          begin
            vm = @compute_client.vm_clone(
              'name'          => attrs[:nodename],
              'datacenter'    => attrs[:datacenter],
              'template_path' => attrs[:image],
              'numCPUs'       => FLAVOR[attrs[:flavor].to_sym][:cores],
              'memoryMB'      => FLAVOR[attrs[:flavor].to_sym][:memory] / (1024 * 1024),
              'power_on'      => false,
              'wait'          => true,
            )
          rescue Exception => e
            raise Errors::ProviderError, "#{__method__}: #{e}"
          end

          @compute_client.servers.get(vm['new_vm']['id'])
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
        
        def add_interfaces(vm, interfaces_config)
          Dopv::log.info("Provider: Vsphere: Node #{vm.name}: #{__method__}: Trying to add interfaces.")
          # Remove all interfaces defined by the template
          Dopv::log.debug("Provider: Vsphere: Node #{vm.name}: #{__method__}: Removing interfaces defined by template.")
          vm.interfaces.each(&:destroy)
          # Create interfaces from scratch
          interfaces_config.each do |config|
            Dopv::log.debug("Provider: Vsphere: Node #{vm.name}: #{__method__}: Creating interface #{config[:name]} in #{config[:network]}.")
            vm.interfaces.create(
              :name     => config[:name],
              :network  => config[:network],
              :type     => 'VirtualVmxnet3'
            )
          end

          # Explicitly reload nics & return VM
          vm.interfaces.reload
          vm
        end

        def assign_affinity_groups(vm, affinity_groups)
          Dopv::log.info("Provider: Vsphere: Node #{vm.name}: #{__method__}: Trying to assign affinity groups.")
          if affinity_groups
            affinity_groups.each do |ag_name|
              ag_id = get_affinity_group_id(ag_name)
              Dopv::log.debug("Provider: Vsphere: Node #{vm.name}: #{__method__}: Assigning affinity group #{ag_name}.")
              vm.add_to_affinity_group(:id => ag_id)
              vm.wait_for { !locked? }
            end
          end
          vm
        end

        def add_disks(vm, config_disks, disk_db)
          Dopv::log.info("Provider: Vsphere: Node #{vm.name}: #{__method__}: Trying to add disks.")
              
          Dopv::log.debug("Provider: Vsphere: Node #{vm.name}: #{__method__}: Loading persistent disks DB.")
          persistent_disks = disk_db.find_all {|pd| pd.node == vm.name}
          
          # Check if persistent disks DB is consistent
          Dopv::log.debug("Provider: Vsphere: Node #{vm.name}: #{__method__}: Checking DB integrity.")
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
            Dopv::log.debug("Provider: Vsphere: Node #{vm.name}: #{__method__}: Attaching disk #{pd.name} [#{pd.id}].")
            vm.attach_volume(:id => pd.id)
            vm.wait_for { !locked? }
          end

          # Create those disks that do not exist in peristent disks DB and
          # record them into DB
          config_disks.each do |cd|
            unless vm.volumes.find {|vol| vol.alias == cd[:name]}
              Dopv::log.debug("Provider: Vsphere: Node #{vm.name}: #{__method__}: Creating disk #{cd[:name]} [#{cd[:size]}].")
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
              Dopv::log.debug("Provider: Vsphere: Node #{vm.name}: #{__method__}: Recording disk #{cd[:name]} into DB.")
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

        def customize(instance, settings)
          nics = []

          # Settings related to each NIC
          settings[:interfaces].each do |nic|
            ip_settings = RbVmomi::VIM::CustomizationIPSettings.new
            if nic[:ip_address] == 'dhcp'
              ip_settings.ip = RbVmomi::VIM::CustomizationDhcpIpGenerator.new
            else
              ip_settings.ip = RbVmomi::VIM::CustomizationFixedIp('ipAddress' => nic[:ip_address])
              ip_settings.subnetMask = nic[:ip_netmask]
              ip_settings.gateway = [nic[:ip_gateway]] if nic[:set_gateway]
            end
            nics << ip_settings
          end

          # Global network settings
          global_ip_settings = RbVmomi::VIM::CustomizationGlobalIPSettings.new
          global_ip_settings.dnsServerList = (settings[:dns][:nameserver] rescue nil)
          global_ip_settings.dnsSuffixList = ([settings[:dns][:domain]] rescue nil)

          # Adapters mapping
          nic_setting_map = nics.collect { |nic| RbVmomi::VIM::CustomizationAdapterMapping.new('adapter' => nic)}

          # Identity settings
          fqdn = settings[:fqdn] || settings[:nodename]
          hostname = fqdn.split('.').first
          domainname = fqdn.gsub(/^[^.]+\./, '')

          identity_settings = case GUEST_ID_TO_OS_FAMILY[instance.guest_id.to_sym]
                              when :linux
                                RbVmomi::VIM::CustomizationLinuxPrep.new(
                                  :domain   => domainname,
                                  :hostName => RbVmomi::VIM::CustomizationFixedName.new(:name => hostname)
                                )
                              when :windows
                                #RbVmomi::VIM::CustomizationSysprep.new(
                                #)
                                raise Errors::ProviderError, "#{__method__} #{instance.name}: Windows guests are currently unsupported"
                              else
                                raise Errors::ProviderError, "#{__method__} #{instance.name}: Unsupported guest type"
                              end

          RbVmomi::VIM::CustomizationSpec.new(
            :identity => identity_settings,
            :globalIPSettings => global_ip_settings,
            :nicSettingMap => nic_setting_map
          )
        end
      end
    end
  end
end
