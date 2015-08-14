require 'rbvmomi'
require 'digest/sha2'
require 'fog'

module Dopv
  module Infrastructure
    class Vsphere < Base
      def initialize(node_config, data_disks_db)
        super(node_config, data_disks_db)

        @compute_connection_opts = {
          :provider                     => 'vsphere',
          :vsphere_username             => provider_username,
          :vsphere_password             => provider_password,
          :vsphere_server               => provider_host,
          :vsphere_port                 => provider_port,
          :vsphere_expected_pubkey_hash => provider_pubkey_hash
        }

        @node_creation_opts = {
          'name'          => nodename,
          'datacenter'    => datacenter.name,
          'template_path' => template_path,
          'dest_folder'   => dest_folder,
          'numCPUs'       => cores,
          'memoryMB'      => memory(:megabyte),
        }
      end

      private

      def template_path
        @node_config[:image]
      end

      def dest_folder
        @node_config[:dest_folder] || ''
      end

      def searchdomains
        begin
          case ns_config[:domain]
          when String
            [ns_config[:domain]]
          when Array
            ns_config
          else
            nil
          end
        rescue nil
        end
      end

      def timezone
        super || '085'
      end

      def node_instance_stopped?(node_instance)
        !node_instance.ready?
      end

      def create_node_instance
        ::Dopv::log.info("Node #{nodename}: Creating node instance.")
        @node_creation_opts['datastore'] = default_pool if default_pool
        vm = compute_provider.vm_clone(@node_creation_opts.merge(
          'power_on'  => false,
          'wait'      => true))
        compute_provider.servers.get(vm['new_vm']['id'])
      end

      def customize_node_instance(node_instance)
        ::Dopv::log.info("Node #{nodename}: Customizing node.")
        # Settings related to each network interface
        ip_settings = interfaces_config.collect do |i|
          ip_setting = ::RbVmomi::VIM::CustomizationIPSettings.new
          if i[:ip_address] == 'dhcp'
            ip_setting.ip = ::RbVmomi::VIM::CustomizationDhcpIpGenerator.new
          else
            ip_setting.ip = ::RbVmomi::VIM::CustomizationFixedIp('ipAddress' => i[:ip_address])
            ip_setting.subnetMask = i[:ip_netmask]
            ip_setting.gateway = [i[:ip_gateway]] if set_gateway?(i)
          end
          ip_setting
        end

        # Adapters mapping
        nic_setting_map = ip_settings.collect { |s| RbVmomi::VIM::CustomizationAdapterMapping.new('adapter' => s) }

        # Global network settings
        global_ip_settings = RbVmomi::VIM::CustomizationGlobalIPSettings.new(
          :dnsServerList => nameservers,
          :dnsSuffixList => searchdomains
        )

        # Identity settings
        identity_settings = case guest_id_to_os_family(node_instance)
                            when :linux
                              RbVmomi::VIM::CustomizationLinuxPrep.new(
                                :domain => domainname,
                                :hostName => RbVmomi::VIM::CustomizationFixedName.new(:name => hostname)
                              )
                            when :windows
                              password_settings = (RbVmomi::VIM::CustomizationPassword.new(
                                :plainText => true,
                                :value => administrator_password
                              ) rescue nil)
                              RbVmomi::VIM::CustomizationSysprep.new(
                                :guiRunOnce => nil,
                                :guiUnattended => RbVmomi::VIM::CustomizationGuiUnattended.new(
                                  :autoLogon => false,
                                  :autoLogonCount => 1,
                                  :password => password_settings,
                                  :timeZone => timezone
                              ),
                                :identification => RbVmomi::VIM::CustomizationIdentification.new(
                                  :domainAdmin => nil,
                                  :domainAdminPassword => nil,
                                  :joinDomain => nil
                              ),
                                :userData => RbVmomi::VIM::CustomizationUserData.new(
                                  :computerName => RbVmomi::VIM::CustomizationFixedName.new(:name => hostname),
                                  :fullName => administrator_fullname,
                                  :orgName => organization_name,
                                  :productId => product_id
                              )
                              )
                            else
                              raise ProviderError, "Unsupported guest OS type"
                            end

        custom_spec = RbVmomi::VIM::CustomizationSpec.new(
          :identity => identity_settings,
          :globalIPSettings => global_ip_settings,
          :nicSettingMap => nic_setting_map
        )
        custom_spec.options = RbVmomi::VIM::CustomizationWinOptions.new(
          :changeSID => true,
          :deleteAccounts => false
        ) if guest_id_to_os_family(node_instance) == :windows

        custom_spec
      end

      def start_node_instance(node_instance)
        customization_spec = super(node_instance)
        customize_node_task(node_instance, customization_spec)
        node_instance.start
      end

      def add_node_nics(node_instance)
        ::Dopv::log.info("Node #{nodename}: Trying to add interfaces.")

        # Remove all interfaces defined by the template
        remove_node_nics(node_instance)

        # Create interfaces from scratch
        interfaces_config.each do |i|
          log_msg = i[:virtual_switch].nil? ?
            "Node #{nodename}: Creating interface #{i[:name]} in #{i[:network]}." :
            "Node #{nodename}: Creating interface #{i[:name]} in #{i[:network]} (#{i[:virtual_switch]})."
          ::Dopv::log.debug(log_msg)
          attrs = {
            :name => i[:name],
            :datacenter => node_instance.datacenter,
            :network => i[:network],
            :virtualswitch => i[:virtual_switch],
            :type => 'VirtualVmxnet3'
          }
          add_node_nic(node_instance, attrs)
        end
      end

      def add_node_volume(node_instance, attrs)
        config = {
          :datastore => attrs[:pool],
          :size => get_size(attrs[:size], :kilobyte),
          :mode => 'persistent',
          :thin => true
        }
        volume = node_instance.volumes.create(config)
        node_instance.volumes.reload
        volume.name = attrs[:name]
        volume
      end

      def destroy_node_volume(node_instance, volume)
        volume_instance = node_instance.volumes.find { |v| v.filename == volume.id }
        volume_instance.destroy
        node_instance.volumes.reload
      end

      def attach_node_volume(node_instance, volume)
        backing_info = RbVmomi::VIM::VirtualDiskFlatVer2BackingInfo.new(
          :datastore => volume.pool,
          :fileName => volume.id,
          :diskMode => 'persistent'
        )

        virtual_disk = RbVmomi::VIM::VirtualDisk.new(
          :controllerKey => node_instance.scsi_controller.key,
          :unitNumber => node_instance.volumes.collect { |v| v.unit_number }.max + 1,
          :key => -1,
          :backing => backing_info,
          :capacityInKB => get_size(volume.size, :kilobyte)
        )

        device_spec = RbVmomi::VIM::VirtualDeviceConfigSpec.new(
          :operation => :add,
          :device => virtual_disk
        )

        config_spec = RbVmomi::VIM::VirtualMachineConfigSpec.new(:deviceChange => [device_spec])

        reconfig_node_task(node_instance, config_spec)
        
        node_instance.volumes.reload
      end

      def detach_node_volume(node_instance, volume)
        volume = node_instance.volumes.all.find { |v| v.filename == volume.id }

        virtual_disk = RbVmomi::VIM::VirtualDisk.new(
          :controllerKey => volume.server.scsi_controller.key,
          :unitNumber => volume.unit_number,
          :key => volume.key,
          :capacityInKB => volume.size
        )

        device_spec = RbVmomi::VIM::VirtualDeviceConfigSpec.new(
          :operation => :remove,
          :device => virtual_disk
        )

        config_spec = RbVmomi::VIM::VirtualMachineConfigSpec.new(:deviceChange => [device_spec])

        reconfig_node_task(node_instance, config_spec)
        
        node_instance.volumes.reload
      end

      def record_node_data_volume(volume)
        ::Dopv::log.debug("Node #{nodename}: Recording volume #{volume.name} into DB.")
        volume = {
          :name => volume.name,
          :id   => volume.filename,
          :pool => volume.datastore,
          :size => volume.size*KILO_BYTE
        }
        super(volume)
      end

      def guest_id_to_os_family(node_instance)
        # Based on http://pubs.vmware.com/vsphere-50/index.jsp?topic=/com.vmware.wssdk.apiref.doc_50/vim.vm.GuestOsDescriptor.GuestOsIdentifier.html
        lookup_table = {
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

        lookup_table[node_instance.guest_id.to_sym] rescue nil
      end

      def reconfig_node_task(node_instance, reconfig_spec)
        node_ref = compute_provider.send(:get_vm_ref, node_instance.id)
        node_ref.ReconfigVM_Task(:spec => reconfig_spec).wait_for_completion
      end

      def customize_node_task(node_instance, customization_spec)
        node_ref = compute_provider.send(:get_vm_ref, node_instance.id)
        node_ref.CustomizeVM_Task(:spec => customization_spec).wait_for_completion
      end

      def organization_name
        raise ProviderError, "Organization name is not defined" unless @node_config[:organization_name]
        @node_config[:organization_name]
      end

      def product_id
        @node_config[:product_id] || ''
      end

      def provider_pubkey_hash
        unless @compute_connection_opts && @compute_connection_opts[:vsphere_expected_pubkey_hash]
          unless @node_config[:provider_pubkey_hash]
            connection = ::RbVmomi::VIM.new(
              :host     => provider_host,
              :port     => provider_port,
              :ssl      => provider_scheme == 'https',
              :ns       => 'urn:vim25',
              :rev      => '4.0',
              :insecure => true
            )
            pubkey_hash = ::Digest::SHA2.hexdigest(connection.http.peer_cert.public_key.to_s)
            connection.close
            pubkey_hash
          else
            @node_config[:provider_pubkey_hash]
          end
        else
          @compute_connection_opts[:vsphere_expected_pubkey_hash]
        end
      end
    end
  end
end
