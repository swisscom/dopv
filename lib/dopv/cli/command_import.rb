module Dopv
  module Cli

    def self.command_import(base)
      base.class_eval do

        desc 'Import data disks from a file into internal state store of the given plan'
        arg_name 'plan_name data_disks_file'
        command :import do |c|
          c.desc 'Force plan import'
          c.switch [:f, :force], :negatable => false

          c.action do |global_options, options, args|
            help_now!('Import takes exactly two arguments, a plan name and data disks file.') if
              args.empty? || args.length != 2

            plan_name, data_disks_file = args

            exit_now!("The #{data_disks_file} must be a readable file.") unless
              File.file?(data_disks_file) && File.readable?(data_disks_file)

            if !Dopv.export_state(plan_name).empty? && !options[:force]
              exit_now!("The internal plan's state is not empty, please use the '-f|--force' flag to overwrite.")
            end

            Dopv.import_state_file(plan_name, data_disks_file)
          end
        end
      end
    end
  end
end
