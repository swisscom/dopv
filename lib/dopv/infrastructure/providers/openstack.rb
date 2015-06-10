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

        @node_creation_opts = {
          :name         => nodename,
          :image_ref    => template.id,
          :flavor_ref   => flavor.id,
          :nics         => add_network_ports
        }
      end

      private

      def network_provider
        Dopv::log.info("Node #{nodename}: Creating network provider.") unless @network_provider
        @network_provider ||= @network_connection_opts ? ::Fog::Network.new(@network_connection_opts) : nil
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

      def create_node_instance
        Dopv::log.info("Node #{nodename}: Creating node instance.")
        instance = compute_provider.servers.create(@node_creation_opts)
        instance.wait_for { ready? }
        instance.reload
      end

      def destroy_node_instance(node_instance, destroy_data_volumes=false)
        super(node_instance, destroy_data_volumes)

        ::Dopv::log.warn("Node #{nodename}: Destroying network ports.")
        remove_network_ports
      end

      def start_node_instance(node_instance)
      end

      def add_node_data_volumes(node_instance)
      end

      def add_network_port(attrs)
        ::Dopv::log.info("Node #{nodename}: Adding port #{attrs[:name]}.")
        network_provider.ports.create(attrs)
      end

      def add_network_ports
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
        @network_ports.each { |p| p.destroy rescue nil }
        @network_ports = nil
      end

      def fixed_ip(subnet_id, ip_address)
        ret = {:subnet_id => subnet_id}
        %w(dhcp none).include?(ip_address) ? ret : ret.merge(:ip_address => ip_address)
      end
    end
  end
end
