module Dopv
  module Cli

    def self.command_export(base)
      base.class_eval do

        desc 'Export the internal data disks state into a local file'
        arg_name 'plan_name data_disks_file'
        command :export do |c|
          c.action do |global_options, options, args|
            help_now!('Export takes exactly two arguments, plan name and data disks file.') if
              args.empty? || args.length != 2

            plan_name, data_disks_file = args
            data_disks_dir = File.dirname(data_disks_file)

            exit_now!("The #{data_disks_dir} must be a directory writable by the process.") unless
              File.directory?(data_disks_dir) && File.writable?(data_disks_dir)

            Dopv.export_state_file(plan_name, data_disks_file)
          end
        end
      end
    end
  end
end
