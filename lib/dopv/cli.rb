#
# DOPv command line main module
#

require 'gli'
require 'dopv'
require 'dopv/cli/command_validate'
require 'dopv/cli/command_add'
require 'dopv/cli/command_remove'
require 'dopv/cli/command_list'
require 'dopv/cli/command_update'
require 'dopv/cli/command_run'

PROGNAME = 'dopv'

module Dopv
  module Cli
    include GLI::App
    extend self

    trace = false

    program_desc 'DOPv command line tool'
    version Dopv::VERSION

    subcommand_option_handling :normal
    arguments :strict

    desc 'Log file'
    arg_name 'path_to_log_file'
    default_value nil
    flag [:logfile, :l]

    desc 'Verbosity of the command line tool'
    arg_name 'level'
    default_value 'info'
    flag [:verbosity, :v], :must_match => ['debug', 'info', 'warn', 'error', 'fatal']

    desc 'Show stacktrace on crash'
    switch [:trace, :t]

    pre do |global_options,command,options,args|
      ENV['GLI_DEBUG'] = 'true' if global_options[:trace] == true
      ::Dopv.init_file_logger(global_options[:logfile] || STDOUT)
      ::Dopv.log.progname = PROGNAME
      ::Dopv.log.level = ::Logger.const_get(global_options[:verbosity].upcase)
      trace = global_options[:trace]

      true
    end

    on_error do |exception|
      ::Dopv.log.fatal {"#{exception.message}"}
      STDERR.puts "\n#{exception.backtrace.join("\n")}" if trace

      true
    end

    command_validate(self)
    command_add(self)
    command_remove(self)
    command_list(self)
    command_update(self)
    command_run(self, :deploy)
    command_run(self, :undeploy)

  end
end
