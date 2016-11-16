module Dopv
  module Cli

    def self.command_export(base)
      base.class_eval do

        desc 'Export the internal disk state into a local diskdb file'
        command :export do |c|
          c.desc 'The plan name to export'
          c.flag [:plan, :p], :arg_name => 'path_to_plan_file', :required => true

          c.desc 'The local diskdb file to export to'
          c.default_value nil
          c.flag [:diskdb, :d], :arg_name => 'path_to_db_file', :required => true

          c.action do |global_options,options,args|
            Dopv.export_state_file(options[:plan], options[:diskdb])
          end
        end

      end
    end

  end
end

