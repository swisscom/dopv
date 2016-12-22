module Dopv
  module Cli

    def self.command_update(base)
      base.class_eval do

        desc 'Update the plan and/or the plan state for a given plan yaml or plan name.'
        arg_name 'plan_file_or_name'

        command :update do |c|
          c.desc 'Remove the existing disk information and start with a clean state.'
          c.switch [:clear, :c], :default_value => false

          c.desc 'Ignore the update and set the state version to the latest version.'
          c.switch [:ignore, :i], :default_value => false

          c.action do |global_options, options, args|
            help_now!('Update takes exactly one argument, the plan name or file.') if
              args.empty? || args.length != 1

            plan = args[0]

            if Dopv.list.include?(plan)
              Dopv.update_state(plan, options)
            elsif File.file?(plan) && File.readable?(plan)
              Dopv.update_plan(plan, options)
            else
              exit_now!("No such plan '#{plan}' in the store or the plan file doesn't exist or is unreadable.")
            end
          end
        end
      end
    end
  end
end
