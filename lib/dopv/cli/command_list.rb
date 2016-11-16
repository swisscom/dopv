module Dopv
  module Cli

    def self.command_list(base)
      base.class_eval do

        desc 'Show the list of plans in the plan store'
        command :list do |c|
          c.action do |global_options,options,args|
            puts Dopv.list
          end
        end

      end
    end

  end
end

