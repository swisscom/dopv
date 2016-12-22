module Dopv
  module Cli

    def self.command_remove(base)
      base.class_eval do

        desc 'Remove existing plan from the plan store'
        arg_name 'plan_name'

        command :remove do |c|
          c.desc 'Keep the DOPi state file'
          c.switch [:k, :keep_dopi_state], :negatable => false

          c.desc 'Remove the DOPv state file (THIS REMOVES THE DISK STATE!)'
          c.switch [:r, :remove_dopv_state], :negatable => false

          c.action do |global_options, options, args|
            help_now!('Remove take exactly one argument, a plan name.') if
              args.empty? || args.length != 1

            plan_name = args[0]

            Dopv.remove(plan_name, !options[:keep_dopi_state], options[:remove_dopv_state])
          end
        end
      end
    end
  end
end
