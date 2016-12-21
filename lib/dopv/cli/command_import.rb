module Dopv
  module Cli

    def self.command_import(base)
      base.class_eval do

        desc 'Import diskdb file into the internal state store for a given plan'
        arg_name 'plan_name data_disks_file'
        command :import do |c|
          c.desc 'The plan name to import to'
          c.flag [:plan, :p], :arg_name => 'plan_name'

          c.desc 'The local diskdb file to import'
          c.flag [:diskdb, :d], :arg_name => 'data_disks_file'

          c.desc 'Force overwrite if the state is not empty'
          c.switch [:force, :f], :default_value => false

          c.action do |global_options, options, args|
            if args.empty?
              if options[:plan].nil? || options[:diskdb].nil?
                exit_now!('Both, -p/--plan and -d/--diskdb options are required.')
              else
                Dopv.log.warn('This invocation method is deprecated and will be removed in DOPv >= 0.8.0.')
                Dopv.log.warn('Please use dopv [-f|--force] import <plan_name> <data_disk_file>.')
                plan_name, data_disks_file = options[:plan], options[:diskdb]
              end
            else
              if args.length != 2
                exit_now!('Import takes exactly two arguments, plan name and data disks file')
              else
                plan_name, data_disks_file = args
              end
            end

            unless File.exists?(data_disks_file)
              exit_now!("File #{data_disks_file} does not exist!")
            end
            if !Dopv.export_state(plan_name).empty? && !options[:force]
              exit_now!("The intenal state is not empty, please use the '--force' flag to overwrite")
            end
            Dopv.import_state_file(plan_name, data_disks_file)
          end
        end
      end
    end
  end
end

