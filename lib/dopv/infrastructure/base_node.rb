module Dopv
  module Infrastructure
    class BaseNode
      def self.bootstrap(node_definition)
        new(node_definition)
      end

      def initialize(node_definition)
        puts "Not yet implemented, please override: #{node_definition.inspect}"
      end
    end
  end
end
