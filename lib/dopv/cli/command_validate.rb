module Dopv
  module Cli

    def self.command_validate(base)
      base.class_eval do

        desc 'Validate a plan file.'
        arg_name 'plan_file'

        command :validate do |c|
          c.action do |global_options, options, args|
            help_now!('Validate takes excatly one argument, a plan file') if
              args.empty? || args.length != 1

            plan_file = args[0]

            exit_now!("The #{plan_file} must exist and be a readable file") unless
              File.file?(plan_file) && File.readable?(plan_file)

            if Dopv.valid?(plan_file)
              puts('Plan is valid.')
            else
              exit_now!('Plan is NOT valid!')
            end
          end
        end
      end
    end
  end
end
