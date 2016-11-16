module Dopv
  module Cli

    def self.command_run(base, action)
      base.class_eval do

        desc "#{action.to_s.capitalize} a plan"
        command action do |c|
          c.desc "plan name from the store or plan file to #{action.to_s}. If a plan " +
                 'file is given DOPv will run in oneshot mode and add/remove ' +
                 'the plan automatically to the plan store'
          c.flag [:plan, :p], :arg_name => 'path_to_plan_file', :required => true

          c.desc 'Use a local diskdb file and import/export it automatically'
          c.default_value nil
          c.flag [:diskdb, :d], :arg_name => 'path_to_db_file'

          c.action do |global_options,options,args|
            remove = false
            plan_name = nil
            if Dopv.list.include?(options[:plan])
              plan_name = options[:plan]
            elsif File.exists?(options[:plan])
              plan_name = Dopv.add(options[:plan])
              remove = true
            else
              help_now!("the provided plan '#{options[:plan]}' is not an existing file or plan name")
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
              when :deploy   then Dopv.deploy(plan_name)
              when :undeploy then Dopv.undeploy(plan_name)
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
