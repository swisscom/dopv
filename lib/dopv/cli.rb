#
# DOPv command line main module
#

require 'gli'
require 'dopv'

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
    default_value 'STDOUT'
    flag [:logfile, :l]

    desc 'Verbosity of the command line tool'
    arg_name 'level'
    default_value 'info'
    flag [:verbosity, :v], :must_match => ['debug', 'info', 'warn', 'error', 'fatal']

    desc 'Show stacktrace on crash'
    switch [:trace, :t]

    pre do |global_options,command,options,args|
      ::Dopv.log(global_options[:logfile] == 'STDOUT' ? STDOUT : global_options[:logfile])
      ::Dopv.log.progname = PROGNAME
      ::Dopv.log.level = ::Logger.const_get(global_options[:verbosity].upcase)
      trace = global_options[:trace]

      true
    end

    on_error do |exception|
      ::Dopv::log.fatal {"#{exception.message}"}
      STDERR.puts "\n#{exception.backtrace.join("\n")}" if trace

      true
    end

    desc 'Deploy a plan'
    command :deploy do |c|
      c.flag [:plan, :p], :arg_name => 'path_to_plan_file', :required => true
      c.flag [:diskdb, :d], :arg_name => 'path_to_db_file'
      c.action do |global_options,options,args|
        plan_name = Dopv.add(options[:plan])
        Dopv.import_state(plan_name, YAML.load_file(options[:diskdb]))
        begin
          Dopv.deploy(plan_name)
        ensure
          File.open(options[:diskdb], File::RDWR) do |diskdb|
            diskdb << YAML.dump(Dopv.export_state(plan_name))
          end
          Dopv.remove(plan_name, true)
        end
      end
    end

    desc 'Undeploy a plan'
    command :undeploy do |c|
      c.flag [:plan, :p], :arg_name => 'path_to_plan_file', :required => true
      c.flag [:diskdb, :d], :arg_name => 'path_to_db_file'
      c.switch [:rmdisk, :r]
      c.action do |global_options,options,args|
        plan_name = Dopv.add(options[:plan])
        Dopv.import_state(plan_name, YAML.load_file(options[:diskdb]))
        begin
          Dopv.undeploy(plan_name, options[:rmdisk])
        ensure
          File.open(options[:diskdb], File::RDWR) do |diskdb|
            diskdb << YAML.dump(Dopv.export_state(plan_name))
          end
          Dopv.remove(plan_name, true)
        end
      end
    end

    desc 'Validate plan file'
    command :validate do |c|
      c.flag [:plan, :p], :arg_name => 'path_to_plan_file', :required => true
      c.action do |global_options,options,args|
        Dopv.valid?(options[:plan]) ? puts('Plan valid.') : puts('Plan is NOT valid!')
      end
    end

  end
end
