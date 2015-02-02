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
      infrastructures = @plan['infrastructures']
      @plan['nodes'].each do |n, d|
        node = {}
        # Infrastructure provider definitions
        node[:provider] = Infrastructure::SUPPORTED_TYPES[infrastructures[d['infrastructure']]['type'].to_sym]
        node[:provider_username] = infrastructures[d['infrastructure']]['credentials']['username']
        node[:provider_password] = infrastructures[d['infrastructure']]['credentials']['password']
        node[:provider_endpoint] = infrastructures[d['infrastructure']]['endpoint']
        # Node definitions
        node[:nodename] = n
        node[:image]    = d['image']
        node[:flavor]   = d['flavor']
        d['disks'].each { |dsk| (node[:disks] ||= []) << Hash[dsk.map { |k, v| [k.to_sym, v] }] } if d['disks']
        d['infrastructure_properties'].each { |k, v| node[k.to_sym] = v } if d['infrastructure_properties']
        d['interfaces'].each do |k, v|
          interface = {}
          interface[:name] = k
          interface[:network] = v['network']
          interface[:ip_address] = v['ip']
          interface[:ip_netmask] = infrastructures[d['infrastructure']]['networks'][v['network']]['ip_netmask']
          interface[:ip_gateway] = infrastructures[d['infrastructure']]['networks'][v['network']]['ip_defgw']
          (node[:interfaces] ||= []) << interface
        end
        node[:dns] = Hash[d['dns'].map { |k, v| [k.to_sym, v] }] unless d['dns'].nil?
        @nodes << node
        puts @nodes
      end
    end

    def execute
      @nodes.each { |node| Infrastructure::bootstrap(node) }
    end

    private

    def validate
      # A plan must be of a Hash type and it must have at least clouds and nodes
      # definitions.
      raise Errors::PlanError, 'Plan must be of hash type' unless @plan.is_a?(Hash)
      if !@plan.has_key?('infrastructures') || !@plan.has_key?('nodes')
        raise Errors::PlanError, "Plan must define 'infrastructure' and 'nodes' hashes"
      end
      # Infrastructure and node definitions must be groupped into hashes.
      if !@plan['infrastructures'].is_a?(Hash) || !@plan['nodes'].is_a?(Hash)
        raise Errors::PlanError, 'Infrastructures and nodes must be of hash type'
      end
      @plan['infrastructures'].each do |i, d|
        raise Errors::PlanError, "Infrastructure '#{i}' is of unsupported type" unless Infrastructure.supported?(d)
        d['networks'].each_value do |v|
          if !v.is_a?(Hash) || !v['ip_pool'].is_a?(Hash) ||
             !v['ip_netmask'].is_a?(String) || !v['ip_defgw'].is_a?(String) ||
             !v['ip_pool']['from'].is_a?(String) || !v['ip_pool']['to'].is_a?(String)
            raise Errors::PlanError, "Infrastructure '#{i}' has an invalid network definition"
          end
          begin
            IPAddr.new(v['ip_netmask'])
            ip_from   = IPAddr.new(v['ip_pool']['from'])
            ip_to     = IPAddr.new(v['ip_pool']['to'])
            ip_defgw  = IPAddr.new(v['ip_defgw'])
            if ip_from > ip_to || !(ip_defgw < ip_from || ip_defgw > ip_to)
              raise Errors::PlanError, "Infrastructure '#{i}' has an invalid network definition"
            end
          rescue
            raise Errors::PlanError, "Infrastructure '#{i}' has an invalid network definition"
          end
        end
      end
      # A node definition must be defined in nodes hash and it is be referenced
      # by its name.
      # The node definition itself must be of a Hash type and it must contain
      # at least definitions of the infrastructure, image, network and flavor.
      # Again, these must be of a certain type.
      # An infrastructure definition pointed to by node's 'infrastructure' key
      # must exist in infrastructures section of the @plan.
      @plan['nodes'].each do |n, d|
        if !(d.is_a?(Hash) && d['infrastructure'].is_a?(String) && d['flavor'].is_a?(String) &&
             d['image'].is_a?(String) && d['interfaces'].is_a?(Hash))
          raise Errors::PlanError, "Invalid definition of node #{n}"
        end
        raise Errors::PlanError, "Node '#{n}' points to invalid infrastructure" unless @plan['infrastructures'].has_key?(d['infrastructure'])
        if d.has_key?('infrastructure_properties')
          if !d['infrastructure_properties'].is_a?(Hash)
            raise Errors::PlanError, "Node '#{n}' has invalid infrastructure properties definition"
          end
          d['infrastructure_properties'].each do |p, v|
            case p
            when 'datacenter'
              raise Errors::PlanError, "Node '#{n}' has invalid infrastructure properties definition" unless v.is_a?(String)
            when 'cluster'
              raise Errors::PlanError, "Node '#{n}' has invalid infrastructure properties definition" unless v.is_a?(String)
            when 'affinity_group'
              raise Errors::PlanError, "Node '#{n}' has invalid infrastructure properties definition" unless v.is_a?(String)
            when 'keep_ha'
              if v != true && v != false
                raise Errors::PlanError, "Node '#{n}' has invalid infrastructure properties definition"
              end
            else
              raise Errors::PlanError, "Node '#{n}' has invalid infrastructure properties definition"
            end
          end
        end

        # Networks
        d['interfaces'].each do |i, v|
          if !v.is_a?(Hash) || !v['network'].is_a?(String) || !v['ip'].is_a?(String)
            raise Errors::PlanError, "Node '#{n}' has invalid interface definition"
          end
          unless @plan['infrastructures'][d['infrastructure']]['networks'].has_key?(v['network'])
            raise Errors::PlanError, "Node '#{n}' network points to invalid network definition"
          end
          if v['ip'] != 'dhcp'
            begin
              ip = IPAddr.new(v['ip'])
              ip_from   = IPAddr.new(@plan['infrastructures'][d['infrastructure']]['networks'][v['network']]['ip_pool']['from'])
              ip_to     = IPAddr.new(@plan['infrastructures'][d['infrastructure']]['networks'][v['network']]['ip_pool']['to'])
              ip_defgw  = IPAddr.new(@plan['infrastructures'][d['infrastructure']]['networks'][v['network']]['ip_defgw'])
              if ip < ip_from || ip > ip_to || ip == ip_defgw
                raise Errors::PlanError, "Node '#{n}' has an invalid IP definition"
              end
            rescue
              raise Errors::PlanError, "Node '#{n}' has an invalid IP definition"
            end
          end
        end

        # Disks
        if d.has_key?('disks')
          raise Errors::PlanError, "Invalid disk definition of node #{n}" unless d['disks'].is_a?(Array)
          d['disks'].each do |dsk|
            if !dsk.is_a?(Hash) || !dsk['name'].is_a?(String) ||
               !dsk['pool'].is_a?(String) || !dsk['size'].is_a?(String) || dsk['size'] !~ /[1-9]*[MGTmgt]/
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
