module Dopv
  module Cli

    def self.command_validate(base)
      base.class_eval do

        desc 'Validate plan file'
        command :validate do |c|
          c.flag [:plan, :p], :arg_name => 'path_to_plan_file', :required => true
          c.action do |global_options,options,args|
            if Dopv.valid?(options[:plan])
              puts('Plan valid.')
            else
              exit_now!('Plan is NOT valid!')
            end
          end
        end

      end
    end

  end
end
