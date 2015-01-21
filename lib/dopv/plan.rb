require 'yaml'
require 'ipaddr'
require 'pry'

module Dopv
  class PlanError < StandardError; end

  class Plan
    def self.load(plan)
      case plan
      when String
        new(YAML.load_file(plan))
      when Hash
        new(plan)
      else
        raise PlanError, "Plan must be of String or Hash type"
      end
    end

    def initialize(plan)
      @nodes = []
      @plan = plan

      validate

      clouds = @plan['clouds']
      @plan['nodes'].each do |n, d|
        node = {}
        # Cloud provider definitions
        node[:provider] = Cloud::SUPPORTED_TYPES[@plan['clouds'][d['cloud']]['type'].to_sym]
        node[:provider_username] = @plan['clouds'][d['cloud']]['credentials']['username']
        node[:provider_password] = @plan['clouds'][d['cloud']]['credentials']['password']
        node[:provider_endpoint] = @plan['clouds'][d['cloud']]['endpoint']
        # Node definitions
        node[:nodename] = n
        node[:image]    = d['image']
        node[:flavor]   = d['flavor']
        node[:disks]    = d['disks'] unless d['disks'].nil?
        # OS/Cloudinit definitions
        node[:nets] = []
        d['nets'].each do |net|
          nic = {}
          nic[:int]   = net['int']
          nic[:proto] = net['proto']
          if net['proto'] == 'static'
            nic[:ip] = net['ip']
            nic[:netmask] = net['netmask']
            nic[:gateway] = net['gateway']
          end
          node[:nets] << nic
        end
        # DNS
        node[:dns] = d['dns'] unless d['dns'].nil?

        @nodes << node
      end
    end

    def execute
      @nodes.each { |node| 
        Object.const_get("Dopv::Cloud::#{node[:provider].capitalize}::Node").bootstrap(node)
      }
    end


    private

    def validate
      # A plan must be of a Hash type and it must have at least clouds and nodes
      # definitions.
      raise PlanError, 'Plan must be of hash type' unless @plan.is_a?(Hash)
      if !@plan.has_key?('clouds') || !@plan.has_key?('nodes')
        raise PlanError, "Plan must define 'clouds' and 'nodes' hashes"
      end
      # Cloud and node definitions must be groupped into hashes.
      if !@plan['clouds'].is_a?(Hash) || !@plan['nodes'].is_a?(Hash)
        raise PlanError, 'Nodes and clouds must be of hash type'
      end
      @plan['clouds'].each do |n, c|
        raise PlanError, "Cloud #{n} is of unsupported type" unless Dopv::Cloud.supported?(c)
      end
      # A node definition in a plan must be defined in nodes hash of the plan
      # and it may be referenced by its name.
      # The node definition itself must be of a Hash type and it must contain
      # at least definitions of cloud, image, nets and flavor. These must be of
      # a certain type. A cloud definition pointed to by node's 'cloud' key must
      # exist in cloud section of the @plan.
      @plan['nodes'].each do |n, d|
        if !(d.is_a?(Hash) && d['cloud'].is_a?(String) && d['flavor'].is_a?(String) &&
             d['image'].is_a?(String) && d['nets'].is_a?(Array))
          raise PlanError, "Invalid definition of node #{n}"
        end
        raise PlanError, "Invalid cloud definition for node #{n}" unless @plan['clouds'].has_key?(d['cloud'])

        # Networks
        d['nets'].each do |net|
          if !net.is_a?(Hash) || !net['int'].is_a?(String) || !net['proto'].is_a?(String)
            raise PlanError, "Invalid network definition for node #{n}"
          end
          if net['proto'] != 'static' && net['proto'] != 'dhcp'
            raise PlanError, "Invalid network protocol definition for node #{n}"
          end
          if net['proto'] == 'static'
            #binding.pry
            begin
              IPAddr.new(net['ip'])
              IPAddr.new(net['netmask'])
              IPAddr.new(net['gateway'])
            rescue
              raise PlanError, "Either of ip, netmask, gateway is invalid or indefined for node #{n}"
            end
          end
        end

        # Disks
        if d.has_key?('disks')
          raise PlanError, "Invalid disk definition of node #{n}" unless d['disks'].is_a?(Hash)
          d['disks'].each do |dsk,size|
            if !dsk.is_a?(String) || size !~ /[1-9]*[MGTmgt]/
              raise PlanError, "Invalid disk name and/or size definition of node #{n}"
            end
          end
        end

        # DNS
        if d.has_key?('dns')
          if !d['dns'].is_a?(Hash) || !d['dns']['nameserver'].is_a?(Array)
            raise PlanError, "Invalid dns specification of node #{n}"
          end
          d['dns']['nameserver'].each do |srv|
            begin
              IPAddr.new(srv)
            rescue
              raise PlanError, "Invalid name server definition of node #{n}"
            end
          end
          if d['dns'].has_key?('domain') && !d['dns']['domain']
            raise PlanError, "Invalid search domain definition of node #{n}"
          end
        end
      end
    end
  end
end
