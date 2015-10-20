require 'fog'
require 'uri'
require 'open-uri'

module Dopv
  module Infrastructure
    class Ovirt < Base
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
          :name       => nodename,
          :template   => template.id,
          :cores      => cores,
          :memory     => memory,
          :storage    => storage,
          :cluster    => cluster.id,
          :ha         => keep_ha?,
          :clone      => full_clone?
        }
      end

      private

      def compute_provider
        unless @compute_provider
          super
          ::Dopv::log.debug("Node #{nodename}: Recreating client with proper datacenter.")
          @compute_connection_opts[:ovirt_datacenter] = datacenter[:id]
          @compute_provider = ::Fog::Compute.new(@compute_connection_opts)
        end
        @compute_provider
      end

      def wait_for_task_completion(node_instance)
        node_instance.wait_for { !locked? }
      end

      def create_node_instance
        node_instance = super

        # For each disk, set up wipe after delete flag
        node_instance.volumes.each do |v|
          ::Dopv::log.debug("Node #{nodename}: Setting wipe after delete for disk #{v.alias}.")
          update_node_volume(node_instance, v, {:wipe_after_delete => true})
        end

        node_instance
      end

      def customize_node_instance(node_instance)
        ::Dopv::log.info("Node #{nodename}: Customizing node.")
        customization_opts = {
          :hostname => fqdn,
          :dns => nameservers,
          :domain => searchdomains,
          :user => 'root',
          :password => root_password,
          :ssh_authorized_keys => root_ssh_keys
        }

        customization_opts[:nicsdef] = interfaces_config.collect do |i|
          nic = {}
          nic[:nicname] = i[:name]
          nic[:on_boot] = 'true'
          nic[:boot_protocol] = case i[:ip_address]
                                when 'dhcp'
                                  'DHCP'
                                when 'none'
                                  'NONE'
                                else
                                  'STATIC'
                                end
          unless i[:ip_address] == 'dhcp' || i[:ip_address] == 'none'
            nic[:ip] = i[:ip_address]
            nic[:netmask] = i[:ip_netmask]
            nic[:gateway] = i[:ip_gateway] if i[:set_gateway]
          end
          nic
        end

        customization_opts
      end

      def start_node_instance(node_instance)
        customization_opts = super(node_instance)
        node_instance.service.vm_start_with_cloudinit(
          :id => node_instance.id,
          :user_data => customization_opts
        )
      end

      def add_node_nic(node_instance, attrs)
        nic = node_instance.add_interface(attrs)
        node_instance.interfaces.reload
        nic
      end

      def update_node_nic(node_instance, nic, attrs)
        node_instance.update_interface(attrs.merge({:id => nic.id}))
        node_instance.interfaces.reload
      end

      def add_node_nics(node_instance)
        ::Dopv::log.info("Node #{nodename}: Trying to add interfaces.")

        # Remove all interfaces defined by the template
        remove_node_nics(node_instance) { |n, i| n.destroy_interface(:id => i.id) }

        # Reserve MAC addresses
        (1..interfaces_config.size).each do |i|
          name = "tmp#{i}"
          ::Dopv::log.debug("Node #{nodename}: Creating interface #{name}.")
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
        ic = interfaces_config.reverse
        node_instance.interfaces.sort_by do |n| n.mac
          i = ic.pop
          ::Dopv::log.debug("Node #{nodename}: Configuring interface #{n.name} (#{n.mac}) as #{i[:name]} in #{i[:network]}.")
          attrs = {
            :name => i[:name],
            :network_name => i[:network],
          }
          update_node_nic(node_instance, n, attrs)
        end
      end

      def add_node_affinity(node_instance, name)
        affinity_group = compute_provider.affinity_groups.find { |g| g.name == name }
        raise ProviderError, "No such affinity group #{name}" unless affinity_group
        ::Dopv::log.info("Node #{nodename}: Adding node to affinity group #{name}.")
        node_instance.add_to_affinity_group(:id => affinity_group.id)
      end

      def add_node_volume(node_instance, attrs)
        storage_domain = compute_provider.storage_domains.find { |d| d.name == attrs[:pool] }
        raise ProviderError, "No such storage domain #{attrs[:storage_domain]}" unless storage_domain

        config = {
          :alias => attrs[:name],
          :size => get_size(attrs[:size]),
          :bootable => 'false',
          :wipe_after_delete => 'true',
          :storage_domain => storage_domain.id,
        }

        config.merge!(:format => 'raw', :sparse => 'false') unless thin_provisioned?(attrs)

        node_instance.add_volume(config)
        wait_for_task_completion(node_instance)
        # This call updates the list of volumes -> no need to call reload.
        node_instance.volumes.find { |v| v.alias == config[:alias] }
      end

      def destroy_node_volume(node_instance, volume)
        node_instance.destroy_volume(:id => volume.id)
        wait_for_task_completion(node_instance)
        node_instance.volumes.reload
      end
      
      def attach_node_volume(node_instance, volume)
        node_instance.attach_volume(:id => volume.id)
        wait_for_task_completion(node_instance)
        node_instance.volumes.reload
      end

      def detach_node_volume(node_instance, volume)
        node_instance.detach_volume(:id => volume.id)
        wait_for_task_completion(node_instance)
        node_instance.volumes.reload
      end
      
      def record_node_data_volume(volume)
        ::Dopv::log.debug("Node #{nodename}: Recording volume #{volume.alias} into DB.")
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
