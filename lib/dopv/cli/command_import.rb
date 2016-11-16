module Dopv
  module Cli

    def self.command_import(base)
      base.class_eval do

        desc 'Import a diskdb file into the internal state store'
        command :import do |c|
          c.desc 'The plan name to import to'
          c.flag [:plan, :p], :arg_name => 'path_to_plan_file', :required => true

          c.desc 'The local diskdb file to import'
          c.default_value nil
          c.flag [:diskdb, :d], :arg_name => 'path_to_db_file', :required => true

          c.desc 'Force overwrite if the state is not empty'
          c.default_value false
          c.switch [:force, :f]

          c.action do |global_options,options,args|
            unless File.exists?(options[:diskdb])
              exit_now!("File #{options[:diskdb]} does not exist!")
            end
            if !Dopv.export_state(options[:plan]).empty? and !options[:force]
              exit_now!("The intenal state is not empty, please use the '--force' flag to overwrite")
            end
            Dopv.import_state_file(options[:plan], options[:diskdb])
          end
        end

      end
    end

  end
end

