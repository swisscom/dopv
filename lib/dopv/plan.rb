require 'yaml'
require 'ipaddr'

module Dopv
  class Plan
    def self.load(plan)
      case plan
      when String
        new(YAML.load_file(plan))
      when Hash
        new(plan)
      else
        raise Errors::PlanError, "Plan argument must be of String or Hash type"
      end
    end

    def initialize(plan)
      @nodes = []
      @plan = plan
      # Validate plan
      validate
      # Generate node definition according to plan
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
        node[:datacenter] = d['datacenter']
        node[:cluster] = d['cluster']
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
        node[:dns] = Hash[d['dns'].map { |k, v| [k.to_sym, v] }] unless d['dns'].nil?
        @nodes << node
      end
    end

    def execute
      @nodes.each { |node| Cloud::bootstrap(node) }
    end

    private

    def validate
      # A plan must be of a Hash type and it must have at least clouds and nodes
      # definitions.
      raise Errors::PlanError, 'Plan must be of hash type' unless @plan.is_a?(Hash)
      if !@plan.has_key?('clouds') || !@plan.has_key?('nodes')
        raise Errors::PlanError, "Plan must define 'clouds' and 'nodes' hashes"
      end
      # Cloud and node definitions must be groupped into hashes.
      if !@plan['clouds'].is_a?(Hash) || !@plan['nodes'].is_a?(Hash)
        raise Errors::PlanError, 'Nodes and clouds must be of hash type'
      end
      @plan['clouds'].each do |n, c|
        raise Errors::PlanError, "Cloud #{n} is of unsupported type" unless Cloud.supported?(c)
      end
      # A node definition in a plan must be defined in nodes hash of the plan
      # and it may be referenced by its name.
      # The node definition itself must be of a Hash type and it must contain
      # at least definitions of cloud, image, nets and flavor. These must be of
      # a certain type. A cloud definition pointed to by node's 'cloud' key must
      # exist in cloud section of the @plan.
      @plan['nodes'].each do |n, d|
        if !(d.is_a?(Hash) && d['cloud'].is_a?(String) &&
             d['flavor'].is_a?(String) && d['datacenter'].is_a?(String) &&
             d['cluster'].is_a?(String) && d['image'].is_a?(String) && d['nets'].is_a?(Array))
          raise Errors::PlanError, "Invalid definition of node #{n}"
        end
        raise Errors::PlanError, "Invalid cloud definition for node #{n}" unless @plan['clouds'].has_key?(d['cloud'])

        # Networks
        d['nets'].each do |net|
          if !net.is_a?(Hash) || !net['int'].is_a?(String) || !net['proto'].is_a?(String)
            raise Errors::PlanError, "Invalid network definition for node #{n}"
          end
          if net['proto'] != 'static' && net['proto'] != 'dhcp'
            raise Errors::PlanError, "Invalid network protocol definition for node #{n}"
          end
          if net['proto'] == 'static'
            begin
              IPAddr.new(net['ip'])
              IPAddr.new(net['netmask'])
              IPAddr.new(net['gateway'])
            rescue
              raise Errors::PlanError, "Either of ip, netmask, gateway is invalid or indefined for node #{n}"
            end
          end
        end

        # Disks
        if d.has_key?('disks')
          raise Errors::PlanError, "Invalid disk definition of node #{n}" unless d['disks'].is_a?(Hash)
          d['disks'].each do |dsk,size|
            if !dsk.is_a?(String) || size !~ /[1-9]*[MGTmgt]/
              raise Errors::PlanError, "Invalid disk name and/or size definition of node #{n}"
            end
          end
        end

        # DNS
        if d.has_key?('dns')
          if !d['dns'].is_a?(Hash) || !d['dns']['nameserver'].is_a?(Array)
            raise Errors::PlanError, "Invalid dns specification of node #{n}"
          end
          d['dns']['nameserver'].each do |srv|
            begin
              IPAddr.new(srv)
            rescue
              raise Errors::PlanError, "Invalid name server definition of node #{n}"
            end
          end
          if d['dns'].has_key?('domain') && !d['dns']['domain']
            raise Errors::PlanError, "Invalid search domain definition of node #{n}"
          end
        end
      end
    end
  end
end
