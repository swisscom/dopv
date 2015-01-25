module Dopv
  module Errors
    # Plan errors
    class PlanError < StandardError; end
    # Cloud proivder errors
    class ProviderError < StandardError; end
  end
end
