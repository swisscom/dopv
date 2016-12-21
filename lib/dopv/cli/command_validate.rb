module Dopv
  module Cli

    def self.command_validate(base)
      base.class_eval do

        desc 'Validate a plan file'
        arg_name 'plan_file'
        command :validate do |c|
          c.flag [:plan, :p], :arg_name => 'plan_file'
          c.action do |global_options, options, args|
            if args.empty?
              if options[:plan].nil?
                exit_now!('The -p/--plan option is required.')
              else
                Dopv.log.warn('This invocation method is deprecated and will be removed in DOPv >= 0.8.0.')
                Dopv.log.warn('Please use dopv validate <plan_file>.')
                plan_file = options[:plan]
              end
            else
              if args.length != 1
                exit_now!('Validate takes excatly one argument, a plan file')
              else
                plan_file = args[0]
              end
            end

            exit_now!("The #{plan_file} must exist and be a readable file") unless
              File.file?(plan_file) && File.readable?(plan_file)

            if Dopv.valid?(plan_file)
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
