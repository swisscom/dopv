#
# DOPv command line main module
#

require 'gli'
require 'dop_common/cli/node_selection'
require 'dop_common/cli/log'
require 'dop_common/cli/global_options'
require 'dopv'
require 'dopv/cli/command_validate'
require 'dopv/cli/command_add'
require 'dopv/cli/command_remove'
require 'dopv/cli/command_list'
require 'dopv/cli/command_update'
require 'dopv/cli/command_import'
require 'dopv/cli/command_export'
require 'dopv/cli/command_run'
require 'logger/colors'

module Dopv
  module Cli
    include GLI::App
    extend self

    trace = false

    program_desc 'DOPv command line tool'
    version Dopv::VERSION

    subcommand_option_handling :normal
    arguments :strict

    DopCommon::Cli.global_options(self)

    pre do |global,command,options,args|
      DopCommon.configure = global
      ENV['GLI_DEBUG'] = 'true' if global[:trace] == true
      DopCommon::Cli.initialize_logger('dopv.log', global[:log_level], global[:verbosity], global[:trace])
      true
    end

    command_validate(self)
    command_add(self)
    command_remove(self)
    command_list(self)
    command_update(self)
    command_import(self)
    command_export(self)
    command_run(self, :deploy)
    command_run(self, :undeploy)
    command_run(self, :refresh)

  end
end
