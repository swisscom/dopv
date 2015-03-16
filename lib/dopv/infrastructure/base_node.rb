module Dopv
  module Infrastructure
    class BaseNode
      def self.bootstrap(node_definition, disk_db)
        new(node_definition, disk_db)
      end

      def initialize(node_definition, disk_db)
        puts "Not yet implemented, please override: #{node_definition.inspect}"
      end

      private

      def exist?(node_name)
        begin
          @compute_client.servers.find {|vm| vm.name == node_name} ? true : false
        rescue => e
          raise Errors::ProviderError, "#{__method__}: #{e}"
        end
      end

      def get_datacenter(datacenter_name, filters={})
        datacenter = @compute_client.datacenters(filters).find do |dc|
          if dc.is_a?(Hash) && dc.has_key?(:name)
            dc[:name] == datacenter_name
          elsif dc.methods.include?(:name)
            dc.name == datacenter_name
          else
            raise Errors::ProviderError, "#{__method__} #{datacenter_name}: Unsupported datacenter type #{dc.class}"
          end
        end
        raise Errors::ProviderError, "#{__method__} #{datacenter_name}: No such data center" unless datacenter
        datacenter
      end

      def get_datacenter_id(datacenter_name, filters={})
        datacenter = get_datacenter(datacenter_name, filters)
        if datacenter.is_a?(Hash)
          dc[:id]
        else
          dc.id
        end
      end

      def get_cluster(cluster_name, filters={})
        cluster = @compute_client.clusters(filters).find { |cl| cl.name == cluster_name }
        raise Errors::ProviderError, "#{__method__} #{cluster_name}: No such cluster" unless cluster
        cluster
      end

      def get_cluster_id(cluster_name, filters={})
        get_cluster(cluster_name, filters).id
      end

      def get_template(template_name, filters={})
        template = @compute_client.templates.all(filters).find { |tpl| tpl.name == template_name }
        raise Errors::ProviderError, "#{__method__} #{template_name}: No such template" unless template
        template
      end

      def get_template_id(template_name, filters={})
        get_template(template_name, filters).id
      end
    end
  end
end
