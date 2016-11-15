require 'colorize'
require 'socket'
require 'logger'

module Dopv
  LOG_COLORS = {
    :unknown  => :magenta,
    :fatal    => :red,
    :error    => :light_red,
    :warn     => :yellow,
    :info     => :green,
    :debug    => :default
  }
  
  def self.logger=(logger)
    @log = logger
    ::DopCommon.logger = logger
  end

  def self.init_file_logger(logfile = STDOUT)
    ::Dopv.logger = Logger.new(logfile)
    @log.formatter = file_logger_formatter
    @log.level = Logger::INFO
    ::DopCommon.add_log_junction(@log)
  end

  def self.file_logger_formatter
    Proc.new do |severity, datetime, progname, msg|
      timestamp = datetime.strftime("%Y-%m-%d %H:%M:%S.%L")
      hostname = ::Socket.gethostname.split('.').first
      file, line, method = caller[4].sub(/.*\/([0-9a-zA-Z_\-.]+):(\d+):.+`(.+)'/, "\\1-\\2-\\3").gsub(":", " ").split("-")
      pid = "[#{::Process.pid}]".ljust(7)
      logentry  = "#{timestamp} #{hostname} #{progname}#{pid} #{severity.ljust(5)} #{file}:#{line}:#{method}: #{msg}\n"
      logentry.colorize(LOG_COLORS[severity.downcase.to_sym])
    end
  end

  def self.log
    @log ||= (Dopv.logger = Logger.new(STDOUT))
  end
end
