require 'rbvmomi'
require 'digest/sha2'
require 'fog'
require 'resolv'

module Dopv
  module Infrastructure

    class Vsphere < Base
      extend Forwardable

      def_delegators :@plan, :product_id, :organization_name, :workgroup, :thin_clone, :tags

      def initialize(node_config, data_disks_db, wait_params={})
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
            'template_path' => image,
            'dest_folder'   => dest_folder || '',
            'numCPUs'       => cores,
            'memoryMB'      => memory.mebibytes.to_i
        }

        if infrastructure_properties.cluster
          @node_creation_opts = {
              'resource_pool' => [infrastructure_properties.cluster, '']
          }.merge(@node_creation_opts)
        end

        @wait_params = {
            :maxtime        => 300,
            :delay          => 10
        }.merge(wait_params)
      end

      private

      def dest_folder
        @dest_folder ||= infrastructure_properties.dest_folder
      end

      def timezone
        super || '085'
      end

      def timezone_to_index(timezone)
        lookup_table = {
            'Europe/Zurich'         => 110,
            :default                => 110
        }

        unless timezone.match(/^[1-9][0-9][0-9]$/)
          (lookup_table.key? timezone) ?
              lookup_table[timezone].to_s : lookup_table[:default].to_s
        else
          timezone
        end
      end

      def node_instance_stopped?(node_instance)
        !node_instance.ready?
      end

      def create_node_instance
        ::Dopv::log.info("Node #{nodename}: Creating node instance.")
        @node_creation_opts['datastore'] = infrastructure_properties.default_pool unless infrastructure_properties.default_pool.nil?
        @node_creation_opts['transform'] = thin_clone ? :sparse : :flat unless thin_clone.nil?

        vm = compute_provider.vm_clone(
            @node_creation_opts.merge(
                'power_on'  => false,
                'wait'      => true
            )
        )

        compute_provider.servers.get(vm['new_vm']['id'])
      end

      def customization_domain_credential(domain)
        credentials.find { |c| c.type == :username_password && c.username.start_with?(domain) }
      end

      def customization_domain?(domain)
        cred = customization_domain_credential(domain)
        !cred.nil?
      end

      def customization_domain_password(domain)
        cred = customization_domain_credential(domain)
        cred.nil? ? nil : cred.password
      end

      def customization_domain_username(domain)
        cred = customization_domain_credential(domain)
        cred.nil? ? nil : cred.username.split('\\').last
      end

      def customize_node_instance(node_instance)
        ::Dopv::log.info("Node #{nodename}: Customizing node.")
        # Settings related to each network interface
        ip_settings = interfaces_config.collect do |i|
          ip_setting = ::RbVmomi::VIM::CustomizationIPSettings.new
          if i.ip == :dhcp
            ip_setting.ip = ::RbVmomi::VIM::CustomizationDhcpIpGenerator.new
          else
            ip_setting.ip = ::RbVmomi::VIM::CustomizationFixedIp('ipAddress' => i.ip)
            ip_setting.subnetMask = i.netmask
            ip_setting.gateway = [i.gateway] if i.set_gateway?
          end
          ip_setting
        end

        # Adapters mapping
        nic_setting_map = ip_settings.collect { |s| RbVmomi::VIM::CustomizationAdapterMapping.new('adapter' => s) }

        # Global network settings
        global_ip_settings = RbVmomi::VIM::CustomizationGlobalIPSettings.new(
            :dnsServerList => dns.name_servers,
            :dnsSuffixList => dns.search_domains
        )

        # Identity settings
        identity_settings = case guest_id_to_os_family(node_instance)

                            when :linux

                              RbVmomi::VIM::CustomizationLinuxPrep.new(
                                  :domain => domainname,
                                  :hostName => RbVmomi::VIM::CustomizationFixedName.new(:name => hostname)
                              )

                            when :windows

                              raise ProviderError, "credentials 'Administrator' is missing in plan" unless administrator_password
                              raise ProviderError, "'organization_name' is missing in plan" unless organization_name

                              password_settings = (RbVmomi::VIM::CustomizationPassword.new(
                                  :plainText => true,
                                  :value => administrator_password
                              ) rescue nil)

                              # Declare identification
                              domain ||= customization_domain?(domainname) ? domainname : nil
                              workgroup ||= nil
                              if domain
                                customization_domain_password_settings = (RbVmomi::VIM::CustomizationPassword.new(
                                    :plainText => true,
                                    :value => customization_domain_password(domain)
                                ) rescue nil)
                                customization_id = RbVmomi::VIM::CustomizationIdentification.new(
                                    :joinDomain => domain,
                                    :domainAdmin => customization_domain_username(domain),
                                    :domainAdminPassword => customization_domain_password_settings
                                )
                              elsif workgroup
                                customization_id = RbVmomi::VIM::CustomizationIdentification.new(
                                    :joinWorkgroup => workgroup
                                )
                              else
                                customization_id = RbVmomi::VIM::CustomizationIdentification.new(
                                    :domainAdmin => nil,
                                    :domainAdminPassword => nil,
                                    :joinDomain => nil
                                )
                              end

                              RbVmomi::VIM::CustomizationSysprep.new(
                                  :guiRunOnce => nil,
                                  :guiUnattended => RbVmomi::VIM::CustomizationGuiUnattended.new(
                                      :autoLogon => false,
                                      :autoLogonCount => 1,
                                      :password => password_settings,
                                      :timeZone => timezone_to_index(timezone)
                                  ),
                                  :identification => customization_id,
                                  :userData => RbVmomi::VIM::CustomizationUserData.new(
                                      :computerName => RbVmomi::VIM::CustomizationFixedName.new(:name => hostname),
                                      :fullName => administrator_fullname,
                                      :orgName => organization_name,
                                      :productId => (!product_id ? '' : product_id)
                                  )
                              )
                            else
                              raise ProviderError, "Unsupported guest OS type '#{node_instance.guest_id.to_sym}'"
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

      def stop_node_instance(node_instance, options={})
        super(node_instance, options)
        node_instance.wait_for(@wait_params[:maxtime]){power_state.to_sym == :poweredOff}
      end

      def add_node_nics(node_instance)
        ::Dopv::log.info("Node #{nodename}: Trying to add interfaces.")

        # Remove all interfaces defined by the template
        remove_node_nics(node_instance) do |node, interface|
          Dopv::log.debug("Node #{nodename}: Remove #{interface.name} (#{interface.key}, #{interface.type}, #{interface.network}).")
          deviceChange = compute_provider.send(:create_interface, interface, interface.key, :remove, :datacenter => datacenter.name)
          # workaround in case the network of the interface is nil
          if deviceChange[:device][:backing].respond_to?(:deviceName) and deviceChange[:device][:backing][:deviceName].nil?
            deviceChange[:device][:backing][:deviceName] = ''
          end
          compute_provider.vm_reconfig_hardware('instance_uuid' => interface.server_id,
                                                'hardware_spec' => {
                                                    'deviceChange'=>[deviceChange]
                                                })
        end

        # Create interfaces from scratch
        interfaces_config.each do |i|
          log_msg = i.virtual_switch.nil? ?
                        "Node #{nodename}: Creating interface #{i.name} in #{i.network}." :
                        "Node #{nodename}: Creating interface #{i.name} in #{i.network} (#{i.virtual_switch})."
          ::Dopv::log.debug(log_msg)
          attrs = {
              :name => i.name,
              :datacenter => node_instance.datacenter,
              :network => i.network,
              :virtualswitch => i.virtual_switch,
              :type => 'VirtualVmxnet3'
          }
          add_node_nic(node_instance, attrs)
        end
      end

      def add_node_volume(node_instance, config)
        volume = node_instance.volumes.create(
            :datastore => config.pool,
            :size => config.size.kibibytes.to_i,
            :mode => 'persistent',
            :thin => config.thin?
        )
        node_instance.volumes.reload
        volume.name = config.name
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
            :capacityInKB => volume.size * 1048576
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
            :size => volume.size * 1048576 # Size must be in gibibytes
        }
        super(volume)
      end

      def guest_id_to_os_family(node_instance)
        # Based on http://pubs.vmware.com/vsphere-50/index.jsp?topic=/com.vmware.wssdk.apiref.doc_50/vim.vm.GuestOsDescriptor.GuestOsIdentifier.html
        lookup_table = {
            :asianux8_64Guest       => :linux,
            :centos8_64Guest        => :linux,
            :darwin17_64Guest       => :linux,
            :darwin18_64Guest       => :linux,
            :debian6_64Guest        => :linux,
            :debian6_Guest          => :linux,
            :freebsd11Guest         => :linux,
            :freebsd11_64Guest      => :linux,
            :freebsd12Guest         => :linux,
            :freebsd12_64Guest      => :linux,
            :rhel4_64Guest          => :linux,
            :rhel4Guest             => :linux,
            :rhel5_64Guest          => :linux,
            :rhel5Guest             => :linux,
            :rhel6_64Guest          => :linux,
            :rhel6Guest             => :linux,
            :rhel7_64Guest          => :linux,
            :rhel7Guest             => :linux,
            :rhel8_64Guest          => :linux,
            :sles11_64Guest         => :linux,
            :sles12_64Guest         => :linux,
            :sles13_64Guest         => :linux,
            :sles14_64Guest         => :linux,
            :sles15_64Guest         => :linux,
            :oracleLinuxGuest       => :linux,
            :oracleLinux64Guest     => :linux,
            :oracleLinux8_64Guest   => :linux,
            :other4xLinux64Guest    => :linux,
            :other4xLinuxGuest      => :linux,
            :ubuntu64Guest          => :linux,
            :ubuntuGuest            => :linux,
            :windows7_64Guest       => :windows,
            :windows7Guest          => :windows,
            :windows7Server64Guest  => :windows,
            :windows8_64Guest       => :windows,
            :windows8Guest          => :windows,
            :windows8Server64Guest  => :windows,
            :windows9_64Guest       => :windows,
            :windows9Guest          => :windows,
            :windows9Server64Guest  => :windows,
            :windows10_64Guest      => :windows,
            :windows10Guest         => :windows,
            :windows10Server64Guest => :windows,
            :'windows7srv-64'       => :windows,
            :'windows8srv-64'       => :windows,
            :'windows9srv-64'       => :windows,
            :'windows10srv-64'      => :windows
        }

        node_instance.guest_id ?
            lookup_table[node_instance.guest_id.to_sym] : nil
      end

      def reconfig_node_task(node_instance, reconfig_spec)
        node_ref = compute_provider.send(:get_vm_ref, node_instance.id)
        node_ref.ReconfigVM_Task(:spec => reconfig_spec).wait_for_completion
      end

      def customize_node_task(node_instance, customization_spec)
        node_ref = compute_provider.send(:get_vm_ref, node_instance.id)
        node_ref.CustomizeVM_Task(:spec => customization_spec).wait_for_completion
      end

      def provider_pubkey_hash
        unless @provider_pubkey_hash
          connection = ::RbVmomi::VIM.new(
              :host     => provider_host,
              :port     => provider_port,
              :ssl      => provider_ssl?,
              :ns       => 'urn:vim25',
              :rev      => '4.0',
              :insecure => true
          )
          @provider_pubkey_hash ||= ::Digest::SHA2.hexdigest(connection.http.peer_cert.public_key.to_s)
          connection.close
        end
        @provider_pubkey_hash
      end

      def get_node_ip_addresses(node_instance)
        begin
          is_windows = guest_id_to_os_family(node_instance) == :windows
          raise ProviderError, "VMware Tools not installed" unless node_instance.tools_installed?

          ::Dopv::log.debug("Node #{nodename}: Waiting on VMware Tools for #{@wait_params[:maxtime]} seconds.")
          reload_node_instance(node_instance)
          node_instance.wait_for(@wait_params[:maxtime]){ready?}
          node_instance.wait_for(@wait_params[:maxtime]){tools_running?}
          # raise ProviderError, "VMware Tools Version not supported" if node_instance.tools_version.to_sym == :guestToolsUnmanaged

          node_ref = compute_provider.send(:get_vm_ref, node_instance.id)
          node_ref_guest_net = nil
          start_time = Time.now.to_f
          is_connected = false
          node_ref.guest.net.each do |i| is_connected ||= i.connected end
          raise ProviderError, "No connected network interface available" unless is_connected

          while (Time.now.to_f - start_time) < @wait_params[:maxtime]
            unless node_ref.guest_ip
              sleep @wait_params[:delay]
            else
              node_ref_guest_net = node_ref.guest.net.map(&:ipAddress).flatten.uniq.compact.select{|i| i.match(Resolv::IPv4::Regex) && !(i.start_with?('169.254.') && is_windows)}
              unless node_ref_guest_net.any?
                sleep @wait_params[:delay]
              else
                break
              end
            end
          end
          raise ProviderError, "VMware Tools not ready yet" unless node_ref_guest_net
          node_ref_guest_net

        rescue Exception => e
          ::Dopv::log.debug("Node #{nodename}: Unable to obtain IP Addresses, Error: #{e.message}.")
          [node_instance.public_ip_address].compact.select{|i| i.match(Resolv::IPv4::Regex) && !(i.start_with?('169.254.') && is_windows)}
        end
      end

      def refresh_node_instance(node_instance)
        return unless tags

        begin
          require 'json'
          require 'rest-client'

          ::Dopv::log.debug("Node #{nodename}: Trying to associate tags: #{tags} (requires minimum VMware vSphere 6.0).")

          parse_json_response_block = Proc.new do |response, request, result|
            JSON.parse(response).fetch('value')
          end

          base_uri = "https://#{provider_host}:#{provider_port}/rest/com/vmware/cis"
          session_header = {'vmware-use-header-authn' => ('0'..'z').to_a.shuffle.first(32).join, 'Content-Type' => 'application/json', 'Accept' => 'application/json'}

          session_token = RestClient::Request.execute method: :post, url: "#{base_uri}/session", user: provider_username, password: provider_password, headers: session_header, verify_ssl: false, &parse_json_response_block
          session_header.merge!({'vmware-api-session-id' => session_token})
          session_header.merge!({:cookies => {'vmware-api-session-id' => session_header.fetch('vmware-api-session-id')}})

          # search tags
          found_tags = []
          all_tags = RestClient::Request.execute method: :get, url: "#{base_uri}/tagging/tag", headers: session_header, verify_ssl: false, &parse_json_response_block

          all_tags.each do |tag_id|
            tag = RestClient::Request.execute method: :get, url: "#{base_uri}/tagging/tag/id:#{tag_id}", headers: session_header, verify_ssl: false, &parse_json_response_block
            if tags.include?(tag.fetch('name'))
              ::Dopv::log.debug("Node #{nodename}: Tag '#{tag.fetch('name')}' found.")
              found_tags << tag
            end
          end

          # ensure all tags found
          tags.each do |tag_name|
            result = found_tags.select { |tag| tag.fetch('name') == tag_name }
            ::Dopv::log.warn("Node #{nodename}: Tag '#{tag_name}' not found! (Tag created in '#{provider_host}' and User '#{provider_username}' authorized?)") if result.empty?
          end

          found_tags.each do |tag|
            payload = {'object_id' => {'type' => 'VirtualMachine', 'id' => node_instance.mo_ref}}.to_json
            ::Dopv::log.debug("Node #{nodename}: Associate tag '#{tag.fetch('name')}' to '#{node_instance.mo_ref}'.")
            _assign = RestClient::Request.execute method: :post, url: "#{base_uri}/tagging/tag-association/id:#{tag.fetch('id')}?~action=attach", headers: session_header, verify_ssl: false, payload: payload
          end

        rescue Exception => e
          ::Dopv::log.debug("Node #{nodename}: Unable to assign tags, Error: #{e.message}.")
        end
      end
    end
  end
end
