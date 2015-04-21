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
            #vm = @compute_client.servers.find { |s| s.name == node_config[:nodename] }

            # Add interfaces
            add_interfaces(vm, node_config[:interfaces])

            # Add disks
            add_disks(vm, node_config[:disks], disk_db)

            # Assign affinnity groups
            #vm = assign_affinity_groups(vm, node_config[:affinity_groups])

            # Start the node
            start(vm, customize(vm, node_config))
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
            vm.volumes.all.each do |v|
              if disk = disk_db.find { |d| d.node == vm.name && v.filename == d.id }
                Dopv::log.debug("Provider: Vsphere: Node #{vm.name}: #{__method__}: Trying to detach disk #{disk.name}.")
                detach_volume(v) rescue nil
              end
            end
            Dopv::log.debug("Provider: Vsphere: Node #{vm.name}: #{__method__}: Destroying VM.")
            #vm.destroy
          end
        end

        def create_vm(attrs)
          Dopv::log.info("Provider: Vsphere: Node #{attrs[:nodename]}: #{__method__}: Trying to create VM.")

          begin
            vm = @compute_client.vm_clone(
              'name'          => attrs[:nodename],
              'datacenter'    => attrs[:datacenter],
              'template_path' => attrs[:image],
              'numCPUs'       => get_cores(attrs),
              'memoryMB'      => get_memory(attrs, :megabyte),
              'power_on'      => false,
              'wait'          => true,
            )
          rescue Exception => e
            raise Errors::ProviderError, "#{__method__}: #{e}"
          end

          @compute_client.servers.get(vm['new_vm']['id'])
        end

        def get_affinity_group_id(affinity_group_name)
          raise Errors::ProviderError, "#{__method__}: Not implemented yet"
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
          vm.interfaces.reload
        end

        def assign_affinity_groups(vm, affinity_groups)
          raise Errors::ProviderError, "#{__method__}: Not implemented yet"
        end

        def add_disks(vm, config_disks, disk_db)
          Dopv::log.info("Provider: Vsphere: Node #{vm.name}: #{__method__}: Trying to add disks.")

          Dopv::log.debug("Provider: Vsphere: Node #{vm.name}: #{__method__}: Loading persistent disks DB.")
          persistent_disks = disk_db.select { |pd| pd.node == vm.name }

          # Check if persistent disks DB is consistent
          Dopv::log.debug("Provider: Vsphere: Node #{vm.name}: #{__method__}: Checking DB integrity.")
          persistent_disks.each do |pd|
            # Disk exists in state DB but not in plan
            unless config_disks.find { |cd| pd.name == cd[:name] }
              err_msg = "#{__method__}: Inconsistent disk DB: Disk #{pd.name} exists in DB but not in plan"
              raise Errors::ProviderError, err_msg
            end
          end
          config_disks.each do |cd|
            # Disk exists in a plan but it is not recorded in the state DB for a
            # given node
            if !persistent_disks.empty? && !persistent_disks.find { |pd| cd[:name] == pd.name }
              err_msg = "#{__method__}: Inconsistent disk DB: Disk #{cd[:name]} exists in plan but not in DB"
              raise Errors::ProviderError, err_msg
            end
          end

          # Attach all persistent disks
          persistent_disks.each do |pd|
            Dopv::log.debug("Provider: Vsphere: Node #{vm.name}: #{__method__}: Attaching disk #{pd.name} [#{pd.id}].")
            begin
              attach_volume(vm, pd)
            rescue Exception => e
              err_msg = "#{__method__}: An error occured while attaching #{pd.name}: #{e}"
              raise Errors::ProviderError, err_msg
            end
          end

          # Create those disks that do not exist in peristent disks DB and
          # record them into DB
          config_disks.each do |cd|
            unless persistent_disks.find { |pd| pd.name == cd[:name] }
              Dopv::log.debug("Provider: Vsphere: Node #{vm.name}: #{__method__}: Creating disk #{cd[:name]} [#{cd[:size]}].")
              size_kb = get_size(cd.merge({:type => :size, :unit => :kilobyte}))
              volume = vm.volumes.create(:datastore => cd[:pool], :size => size_kb, :mode => 'persistent', :thin => true)
              # Record volume to a persistent disks database
              Dopv::log.debug("Provider: Vsphere: Node #{vm.name}: #{__method__}: Recording disk #{cd[:name]} into DB.")
              disk_db << {
                :node => vm.name,
                :name => cd[:name],
                :id   => volume.filename,
                :pool => volume.datastore,
                :size => volume.size*KILO_BYTE
              }
              disk_db.save
            end
          end
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

        def attach_volume(instance, disk_entry)
          backing_info = RbVmomi::VIM::VirtualDiskFlatVer2BackingInfo.new(
            :datastore  => disk_entry.pool,
            :fileName   => disk_entry.id,
            :diskMode   => 'persistent'
          )

          unit_number ||= instance.volumes.collect { |v| v.unit_number }.max + 1
          virtual_disk = RbVmomi::VIM::VirtualDisk.new(
            :controllerKey  => instance.scsi_controller.key,
            :unitNumber     => unit_number,
            :key            => -1,
            :backing        => backing_info,
            :capacityInKB   => (disk_entry.size/KILO_BYTE).to_i
          )

          device_spec = RbVmomi::VIM::VirtualDeviceConfigSpec.new(
            :operation  => :add,
            :device     => virtual_disk
          )

          vm_spec = RbVmomi::VIM::VirtualMachineConfigSpec.new(:deviceChange => [device_spec])

          vm_ref = @compute_client.send(:get_vm_ref, instance.id)
          vm_ref.ReconfigVM_Task(:spec => vm_spec).wait_for_completion
        end

        def detach_volume(volume)
          backing_info = RbVmomi::VIM::VirtualDiskFlatVer2BackingInfo.new(
            :datastore  => volume.datastore,
            :fileName   => volume.filename,
            :diskMode   => volume.mode
          )

          virtual_disk = RbVmomi::VIM::VirtualDisk.new(
            :controllerKey  => volume.server.scsi_controller.key,
            :unitNumber     => volume.unit_number,
            :key            => volume.key,
            #:backing        => backing_info,
            :capacityInKB   => volume.size
          )

          device_spec = RbVmomi::VIM::VirtualDeviceConfigSpec.new(
            :operation  => :remove,
            :device     => virtual_disk
          )

          vm_spec = RbVmomi::VIM::VirtualMachineConfigSpec.new(:deviceChange => [device_spec])

          vm_ref = @compute_client.send(:get_vm_ref, volume.server.id)
          vm_ref.ReconfigVM_Task(:spec => vm_spec).wait_for_completion
        end

        def start(instance, customization)
          vm_ref = @compute_client.send(:get_vm_ref, instance.id)
          vm_ref.CustomizeVM_Task(:spec => customization).wait_for_completion
          instance.start
        end
      end
    end
  end
end
