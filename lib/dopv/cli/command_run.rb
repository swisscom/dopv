module Dopv
  module Cli

    def self.command_run(base, action)
      base.class_eval do

        desc "#{action.capitalize} a plan."
        arg_name 'plan_name'

        command action do |c|
          if action == :undeploy
            c.desc 'Remove data disks from the state and cloud provider.'
            c.switch [:rmdisk, :r], :default_value => false
          end

          DopCommon::Cli.node_select_options(c)

          c.action do |global_options, options, args|
            options[:run_for_nodes] = DopCommon::Cli.parse_node_select_options(options)

            help_now!("#{action.capitalize} takes exactly one argument, a plan name.") if
              args.empty? || args.length > 1

            plan_name = args[0]

            begin
              case action
              when :deploy   then Dopv.deploy(plan_name, options)
              when :undeploy then Dopv.undeploy(plan_name, options)
              end
            end
          end
        end
      end
    end
  end
end
