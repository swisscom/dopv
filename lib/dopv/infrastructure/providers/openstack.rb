require 'fog'

module Dopv
  module Infrastructure
    class OpenStack < Base
      def initialize(node_config, data_disks_db)
        super(node_config, data_disks_db)

        @compute_connection_opts = {
          :provider             => 'openstack',
          :openstack_username   => provider_username,
          :openstack_api_key    => provider_password,
          :openstack_tenant     => provider_tenant,
          :openstack_auth_url   => provider_url,
          :connection_options   => {
            :ssl_verify_peer => false
          }
        }

        @network_connection_opts = @compute_connection_opts
        @volume_connection_opts  = @compute_connection_opts

        @node_creation_opts = {
          :name         => nodename,
          :image_ref    => template.id,
          :flavor_ref   => flavor.id,
          :config_drive => true
        }
      end

      private

      def nameservers
        ns_config[:nameserver].join(" ") rescue nil
      end

      def network_provider
        Dopv::log.info("Node #{nodename}: Creating network provider.") unless @network_provider
        @network_provider ||= @network_connection_opts ? ::Fog::Network.new(@network_connection_opts) : nil
      end

      def volume_provider
        Dopv::log.info("Node #{nodename}: Creating volume provider.") unless @volume_provider
        @volume_provider ||= @volume_connection_opts ? ::Fog::Volume.new(@volume_connection_opts) : nil
      end

      def provider_tenant
        @node_config[:tenant]
      end

      def tenant(filters={})
        @tenant ||= compute_provider.tenants(filters).find { |t| t.name == @node_config[:tenant] }
        raise ProviderError, "No such tenant #{@node_config[:tenant]}" unless @tenant
        @tenant
      end

      def flavor(filters={})
        @flavor ||= compute_provider.flavors(filters).find { |f| f.name == @node_config[:flavor] }
        raise ProviderError, "No such flavor #{@node_config[:flavor]}" unless @flavor
        @flavor
      end

      def network(name, filters={})
        net = network_provider.networks(filters).find { |n| n.name == name || n.id == name }
        raise ProviderError, "No such network #{name}" unless net
        net
      end

      def subnet(name, filters={})
        net = network_provider.subnets(filters).find { |s| s.name == name || s.id == name }
        raise ProviderError, "No such subnetwork #{name}" unless net
        net
      end

      def node_instance_stopped?(node_instance)
        !node_instance.ready?
      end

      def wait_for_task_completion(instance)
        instance.wait_for { ready? }
      end

      def create_node_instance
        Dopv::log.info("Node #{nodename}: Creating node instance.")

        @node_creation_opts[:nics] = add_network_ports
        @node_creation_opts[:user_data_encoded] = [cloud_config].pack('m')

        Dopv::log.debug("Node #{nodename}: Spawning node instance.")
        instance = compute_provider.servers.create(@node_creation_opts)
        wait_for_task_completion(instance)

        instance.reload
      end

      def destroy_node_instance(node_instance, destroy_data_volumes=false)
        super(node_instance, destroy_data_volumes)
        remove_network_ports
      end

      def start_node_instance(node_instance)
      end

      def add_node_volume(node_instance, attrs)
        config = {
          :name => attrs[:name],
          :display_name => attrs[:name],
          :size => get_size(attrs[:size], :gigabyte),
          :volume_type => attrs[:pool],
          :description => attrs[:name]
        }
        volume = super(volume_provider, config)
        volume.wait_for { ready? }
        attach_node_volume(node_instance, volume.reload)
        volume.reload
      end

      def attach_node_volume(node_instance, volume)
        volume_instance = node_instance.volumes.all.find { |v| v.id = volume.id }
        node_instance.attach_volume(volume_instance.id, nil)
        volume_instance.wait_for { volume_instance.status.downcase == "in-use" }
        node_instance.volumes.reload
      end

      def detach_node_volume(node_instance, volume)
        node_instance.detach_volume(volume.id)
        volume.wait_for { ready? }
        node_instance.volumes.reload
      end

      def record_node_data_volume(volume)
        ::Dopv::log.debug("Node #{nodename}: Recording volume #{volume.display_name} into DB.")
        volume = {
          :name => volume.display_name,
          :id   => volume.id,
          :pool => volume.volume_type == 'None' ? nil : volume.volume_type,
          :size => volume.size*GIGA_BYTE
        }
        super(volume)
      end

      def add_network_port(attrs)
        ::Dopv::log.debug("Node #{nodename}: Adding network port #{attrs[:name]}.")
        network_provider.ports.create(attrs)
      end

      def add_network_ports
        ::Dopv::log.info("Node #{nodename}: Adding network ports.")
        ports_config = {}
        interfaces_config.each do |i|
          s = subnet(i[:network])
          port_name = "#{nodename}_#{s.network_id}"
          if ports_config.has_key?(port_name)
              ports_config[port_name][:fixed_ips] << fixed_ip(s.id, i[:ip_address])
          else
            ports_config[port_name] = {
              :network_id => s.network_id,
              :fixed_ips => [fixed_ip(s.id, i[:ip_address])]
            }
          end
        end
        @network_ports = ports_config.map { |k,v| add_network_port(v.merge(:name => k)) }
        @network_ports.collect { |p| {:port_id => p.id} }
      end

      def remove_network_ports
        ::Dopv::log.warn("Node #{nodename}: Removing network ports.")
        if @network_ports
          @network_ports.each { |p| p.destroy rescue nil }
          @network_ports = nil
        end
      end

      def fixed_ip(subnet_id, ip_address)
        rval = { :subnet_id => subnet_id }
        %w(dhcp none).include?(ip_address) ? rval : rval.merge(:ip_address => ip_address)
      end

      def cloud_config
        config = "#cloud-config\n"  \
          "hostname: #{hostname}\n" \
          "fqdn: #{fqdn}\n"         \
          "ssh_pwauth: True\n"

        if root_password
          config <<                       \
            "chpasswd:\n"                 \
            "  list: |\n"                 \
            "    root:#{root_password}\n" \
            "  expire: False\n"
        end

        if root_ssh_keys
          config <<                       \
            "users:\n"                    \
            "  - name: root\n"            \
            "    ssh_authorized_keys:\n"
          root_ssh_keys.each { |k| config << "      - #{k}\n" }
        end

        config <<
          "runcmd:\n" \
          "  - service network restart\n"

        config
      end
    end
  end
end
