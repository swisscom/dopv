module Dopv
  module Errors
    # Persistent Disk Errors
    class PersistentDiskError < StandardError; end
    # Plan errors
    class PlanError < StandardError; end
    # Cloud proivder errors
    class ProviderError < StandardError; end
  end
end
