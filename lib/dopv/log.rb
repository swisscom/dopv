module Dopv
  def self.log(logfile = STDOUT)
    @@log ||= Logger.new(logfile)
    @@log.progname = Dopv::PROGNAME
    @@log
  end

  def self.logger=(logger)
    @@log = logger
  end
end
