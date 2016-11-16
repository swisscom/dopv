module Dopv
  module Cli

    def self.command_update(base)
      base.class_eval do

        desc 'Update the plan and/or the plan state for a given plan yaml or plan name.'
        arg_name 'plan'
        command :update do |c|
          c.desc 'Remove the existing disk information and start with a clean state'
          c.default_value false
          c.switch [:clear, :c]

          c.desc 'Ignore the update and set the state version to the latest version'
          c.default_value false
          c.switch [:ignore, :i]

          c.action do |global_options,options,args|
            help_now!('Specify a plan name or  to update') if args.empty?
            help_now!('You can only update one plan') if args.length > 1
            plan = args[0]
            if Dopv.list.include?(plan)
              Dopv.update_state(plan, options)
            elsif File.exists?(plan)
              Dopv.update_plan(plan, options)
            else
              help_now!("the provided plan '#{plan}' is not an existing file or plan name")
            end
          end
        end

      end
    end

  end
end

