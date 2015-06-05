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
          #:nics         => [ { :net_id => "f0c5d190-a0ab-49db-a5c8-47267051974a" } ]
          #:nics         => [ {:net_id => "a7a982ec-e1ae-4dac-842c-cd79e3e98f6b", :v4_fixed_ip => "10.10.0.223" },  { :net_id => "f0c5d190-a0ab-49db-a5c8-47267051974a", :v4_fixed_ip => "10.0.1.223" } ],
#         :nics         => [ { :port_id => "a32c7941-2121-401e-ae73-613f7448c4cb" }, { :port_id => "c91b7806-452e-4253-8c6b-4b0009b391d7" } ]
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

      def subnet(name, filters={})
        sub_net = network_provider.subnets(filters).find { |s| s.name == name }
        raise ProviderError, "No such subnet #{name}" unless sub_net
        sub_net
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

      def add_node_data_volumes(node_instance)
      end

      def add_network_port(attrs)
        network_provider.ports.create(
          :name => "#{nodename}-#{attrs[:network]}-#{attrs[:name]}",
          :network_id => subnet(attrs[:network]).network_id
          :fixed_ips => [
            { :subnet_id => subnet(attrs[:network]).id, :ip_address => attrs[:ip_address] }
          ]
      end

      def add_network_ports
      end
    end
  end
end
