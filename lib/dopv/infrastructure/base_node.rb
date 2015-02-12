module Dopv
  module Infrastructure
    class BaseNode
      def self.bootstrap(node_definition, disk_db)
        new(node_definition, disk_db)
      end

      def initialize(node_definition, disk_db)
        puts "Not yet implemented, please override: #{node_definition.inspect}"
      end
    end
  end
end
