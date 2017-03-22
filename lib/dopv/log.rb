require 'logger'

module Dopv

  def self.log
    @log ||= DopCommon.log
  end

  def self.logger=(logger)
    @log = logger
    DopCommon.logger = logger
  end

end
