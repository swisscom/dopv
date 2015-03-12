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
    end
  end
end
