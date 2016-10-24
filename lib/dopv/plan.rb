require 'forwardable'
require 'yaml'
require 'dop_common'

module Dopv
  class Plan
    extend Forwardable

    attr_reader :plan_parser

    def_delegators :@plan_parser,
      :name,
      :nodes

    def initialize(plan_parser)
      @plan_parser = plan_parser
    end

    def valid?
      @plan_parser.valid?
    end
  end
end
