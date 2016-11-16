module Dopv
  module Cli

    def self.command_undeploy(base)
      base.class_eval do

        desc 'Undeploy a plan'
        command :undeploy do |c|
          c.flag [:plan, :p], :arg_name => 'path_to_plan_file', :required => true
          c.flag [:diskdb, :d], :arg_name => 'path_to_db_file'
          c.switch [:rmdisk, :r]
          c.action do |global_options,options,args|
            plan_name = Dopv.add(options[:plan])
            Dopv.import_state(plan_name, YAML.load_file(options[:diskdb]))
            begin
              Dopv.undeploy(plan_name, options[:rmdisk])
            ensure
              File.open(options[:diskdb], File::RDWR) do |diskdb|
                diskdb << YAML.dump(Dopv.export_state(plan_name))
              end
              Dopv.remove(plan_name, true)
            end
          end
        end

      end
    end

  end
end
