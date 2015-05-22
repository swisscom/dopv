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

        @node_creation_opts = {
          :name        => nodename,
          :image_ref   => template.id,
          :flavor_ref  => flavor.id,
        }
      end

      private

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
    end
  end
end
