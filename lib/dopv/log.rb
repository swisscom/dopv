require 'colorize'
require 'socket'

module Dopv
  LOG_COLORS = {
    :unknown  => :magenta,
    :fatal    => :red,
    :error    => :light_red,
    :warn     => :yellow,
    :info     => :green,
    :debug    => :default
  }

  def self.log_init(logfile)
    @@log ||= Logger.new(logfile)
    @@log.formatter = proc do |severity, datetime, progname, msg|
      timestamp = datetime.strftime("%Y-%m-%d %H:%M:%S.%L")
      hostname  = Socket.gethostname.split('.').first
      logentry  = "#{timestamp} #{hostname} #{progname}[#{Process.pid}]: #{severity.ljust(5)} #{msg}\n"
      logfile == STDOUT ? logentry.colorize(LOG_COLORS[severity.downcase.to_sym]) : logentry
    end
    @@log.level = Logger::INFO
    @@log
  end

  def self.log(logfile = STDOUT)
    @@log ||= log_init(logfile)
  end

  def self.logger=(logger)
    @@log = logger
  end
end