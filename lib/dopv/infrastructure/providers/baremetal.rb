require 'fog'

module Dopv
  module Infrastructure
    class BareMetal < Base
      def bootstrap_node
        ::Dopv::log.info("Node #{nodename}: Bootstrapping node instance (noop).")
        true
      end
    end
  end
end
