module Dopv
  module Infrastructure
    KILO_BYTE = 1024
    MEGA_BYTE = 1024 * KILO_BYTE
    GIGA_BYTE = 1024 * MEGA_BYTE

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

      def get_size(attrs={})
        type = attrs[:type]
        unit = attrs[:unit] || :bytes

        value = case attrs[type]
                when /\d[Mm]/
                  attrs[type].split(/[Mm]/).first.to_i * MEGA_BYTE
                when /\d[Gg]/
                  attrs[type].split(/[Mm]/).first.to_i * GIGA_BYTE
                when nil
                  FLAVOR[:medium][type]
                end
        raise Errors::ProviderError, "#{__method__} #{attrs[type]}: Invalid #{type.to_s} value" unless value > 0

        if attrs[:flavor]
          begin
            value = FLAVOR[attrs[:flavor].to_sym][type]
          rescue
            raise Errors::ProviderError, "#{__method__} #{attrs[:flavor]}: Invalid flavor"
          end
        end

        case unit
        when :gigbyte
          (value / GIGA_BYTE).to_i
        when :megabyte
          (value / MEGA_BYTE).to_i
        else # Bytes
          value
        end
      end

      def get_cores(attrs={})
        cores = case attrs[:cores]
                when Integer
                  attrs[:cores]
                when /\d/
                  attrs[:cores].to_i
                when nil
                  FLAVOR[:medium][:cores]
                end
        raise Errors::ProviderError, "#{__method__} #{attrs[:cores]}: Invalid cores value" unless cores > 0

        if attrs[:flavor]
          begin
            cores = FLAVOR[attrs[:flavor].to_sym][:cores]
          rescue
            raise Errors::ProviderError, "#{__method__} #{attrs[:flavor]}: Invalid flavor"
          end
        end

        cores
      end

      def get_memory(attrs={}, unit=:bytes)
        get_size(attrs.merge(:type => :memory, :unit => unit))
      end

      def get_storage(attrs={}, unit=:bytes)
        get_size(attrs.merge(:type => :storage, :unit => unit))
      end
    end
  end
end
