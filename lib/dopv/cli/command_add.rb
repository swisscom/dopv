module Dopv
  module Cli

    def self.command_add(base)
      base.class_eval do

        desc 'Add a new plan file to the plan store'
        arg_name 'plan_file'

        command :add do |c|
          c.desc 'Update the plan if it already exists in plan store'
          c.switch [:update, :u], :negatable => false

          c.action do |global_options, options, args|
            help_now!('Add takes exactly one argument, a plan file.') if
              args.empty? || args.length != 1

            plan_file = args[0]

            exit_now!("The plan file #{plan_file} must be a readable file.") unless
              File.file?(plan_file) && File.readable?(plan_file)

            begin
              puts Dopv.add(plan_file)
            rescue DopCommon::PlanExistsError => e
              if options[:update]
                puts Dopv.update_plan(plan_file, {})
              else
                raise "#{e}, please use 'dopv update' first, or use -u|--update flag to add this plan forcibly."
              end
            end
          end
        end
      end
    end
  end
end
