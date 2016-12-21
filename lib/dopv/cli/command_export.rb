module Dopv
  module Cli

    def self.command_export(base)
      base.class_eval do

        desc 'Export the internal disk state into a local diskdb file'
        arg_name 'plan_name data_disks_file'
        command :export do |c|
          c.desc 'The plan name to export'
          c.flag [:plan, :p], :arg_name => 'plan_name'

          c.desc 'The local diskdb file to export to'
          c.flag [:diskdb, :d], :arg_name => 'data_disks_file'

          c.action do |global_options, options, args|
            if args.empty?
              if options[:plan].nil? || options[:diskdb].nil?
                exit_now!('Both, -p/--plan and -d/--diskdb options are required.')
              else
                Dopv.log.warn('This invocation method is deprecated and will be removed in DOPv >= 0.8.0.')
                Dopv.log.warn('Please use dopv export <plan_name> <data_disk_file>.')
                plan_name, data_disks_file = options[:plan], options[:diskdb]
              end
            else
              if args.length != 2
                exit_now!('Export takes exactly two arguments, plan file and data disks file')
              else
                plan_name, data_disks_file = args
              end
            end
            Dopv.export_state_file(plan_name, data_disks_file)
          end
        end
      end
    end
  end
end

