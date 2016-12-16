module Dopv
  module Cli

    def self.command_run(base, action)
      base.class_eval do

        desc "#{action.to_s.capitalize} a plan"
        arg_name 'plan_file_or_id'
        command action do |c|
          c.desc "plan name from the store or plan file to #{action.to_s}. If a plan " +
                 'file is given DOPv will run in oneshot mode and add/remove ' +
                 'the plan automatically to the plan store'
          c.flag [:plan, :p], :arg_name => 'path_to_plan_file', :default_value => nil

          c.desc 'Use a local diskdb file and import/export it automatically'
          c.default_value nil
          c.flag [:diskdb, :d], :arg_name => 'path_to_db_file'

          if action == :undeploy
            c.desc 'Remove the disks'
            c.default_value false
            c.switch [:rmdisk, :r]
          end

          DopCommon::Cli.node_select_options(c)

          c.action do |global_options,options,args|
            options[:run_for_nodes] = DopCommon::Cli.parse_node_select_options(options)

            # The action is invoked the old way. XXX: This will be removed in >=
            # 0.8.0.
            if args.empty?
              help_now!('Specify a plan name to run') if options[:plan].nil?
              Dopv.log.warn('This invocation method is deprecated and will be removed in DOPv >= 0.8.0.')
              Dopv.log.warn("Please use new invocation method, i.e. the following workflow: dopv add <plan_file>; dopv #{action} <plan_name>;")

              remove = false
              plan_name = nil

              if Dopv.list.include?(options[:plan])
                plan_name = options[:plan]
              elsif File.exists?(options[:plan])
                begin
                  plan_name = Dopv.add(options[:plan])
                rescue DopCommon::PlanExistsError
                  msg = "Plan #{options[:plan]} already exists in plan cache.\n" +
                    "If you want to #{action} the plan the old way, i.e. by passing its file name as\n" +
                    "an option of #{action} rather than its name as another argument, you will have to\n" +
                    "remove the plan manually.\n" +
                    "Please note that this might lead to undesired side affects such as removal of\n" +
                    "the plan state.\n" +
                    "Please note that infromation about data disks isn't removed upon plan removal."
                  exit_now!(msg)
                end
                Dopv.log.warn("The plan will be removed when #{action} action if finished.")
                remove = true
              else
                help_now!("the provided plan '#{options[:plan]}' is not an existing file or plan name")
              end
            else
              help_now!('Cannot specify a plan as an option and argument at the same time.') unless options[:plan].nil?
              help_now!('You can only run one plan') if args.length > 1

              plan_name = args[0]
            end

            export = false
            if options[:diskdb]
              # check if the db file exists and if that is ok
              unless File.exists?(options[:diskdb])
                if Dopv.export_state(plan_name).empty?
                  msg = "The specified diskdb file #{options[:diskdb]} does not exists" +
                        "and the internal disk store is not empty. Please delete the state " +
                        "first with 'dopv update --clear #{plan_name}' if this is what you " +
                        "want, or correct the diskdb filename"
                  exit_now!(msg)
                end
              else
                Dopv.import_state_file(plan_name, options[:diskdb])
              end
              export = true
            end

            begin
              case action
              when :deploy   then Dopv.deploy(plan_name, options)
              when :undeploy then Dopv.undeploy(plan_name, options)
              end
            ensure
              Dopv.export_state_file(plan_name, options[:diskdb]) if export
              Dopv.remove(plan_name, true) if remove
            end
          end
        end

      end
    end

  end
end
