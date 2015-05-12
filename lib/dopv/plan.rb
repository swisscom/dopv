require 'yaml'
require 'ipaddr'
require 'pry-debugger'

module Dopv
  class Plan
    def self.load(plan, disk_db_file)
      case plan
      when String
        new(YAML.load_file(plan), disk_db_file)
      when Hash
        new(plan, disk_db_file)
      else
        raise Errors::PlanError, "#{__method__}: The plan must be a string or hash"
      end
    end

    def initialize(plan, disk_db_file)
      @nodes = []
      @plan = plan
      @disk_db = PersistentDisk::load(disk_db_file)
      
      Dopv::log.info("Plan: #{__method__}: Creation.")

      # Validate plan
      validate
      
      # Generate node definition according to plan
      Dopv::log.debug("Plan: #{__method__}: Parsing.")
      infrastructures = @plan['infrastructures']
      @plan['nodes'].each do |n, d|
        node = {}
        # Infrastructure provider definitions
        node[:provider] = Infrastructure::SUPPORTED_TYPES[infrastructures[d['infrastructure']]['type'].to_sym]
        node[:provider_username]  = infrastructures[d['infrastructure']]['credentials']['username']
        node[:provider_password]  = infrastructures[d['infrastructure']]['credentials']['password']
        node[:provider_apikey]    = infrastructures[d['infrastructure']]['credentials']['apikey']
        node[:provider_endpoint]  = infrastructures[d['infrastructure']]['endpoint']
        # Node definitions
        node[:nodename]           = n
        node[:fqdn]               = d['fqdn']
        node[:image]              = d['image']
        node[:flavor]             = d['flavor'] if d['flavor']
        node[:cores]              = d['cores'] if d['cores']
        node[:memory]             = d['memory'] if d['memory']
        node[:storage]            = d['storage'] if d['storage']
        node[:full_clone]         = d['full_clone'] unless d['full_clone'].nil?
        node[:product_id]        = d['product_id'] if d['product_id']
        node[:organization_name]  = d['organization_name'] if d['organization_name']
        node[:timezone]           = d['timezone'] if d['timezone']
        # Create an empty disks array
        node[:disks] = []
        # Add disks if any
        if d['disks']
          d['disks'].each do |dsk|
            dsk['pool'] = d['infrastructure_properties']['default_pool'] unless dsk['pool']
            node[:disks] << Hash[dsk.map { |k, v| [k.to_sym, v] }]
          end
        end
        d['infrastructure_properties'].each { |k, v| node[k.to_sym] = v } if d['infrastructure_properties']
        d['interfaces'].each do |k, v|
          interface = {}
          interface[:name] = k
          interface[:network] = v['network']
          if v['ip']
            interface[:ip_address] = v['ip']
            interface[:ip_netmask] = infrastructures[d['infrastructure']]['networks'][v['network']]['ip_netmask']
            if infrastructures[d['infrastructure']]['networks'][v['network']]['ip_defgw']
              interface[:ip_gateway] = infrastructures[d['infrastructure']]['networks'][v['network']]['ip_defgw']
            end
          end
          interface[:set_gateway] = v['set_gateway'] == false ? v['set_gateway'] : true
          interface[:virtual_switch] = v['virtual_switch'] if v['virtual_switch']
          (node[:interfaces] ||= []) << interface
        end
        # Add affinity groups
        node[:affinity_groups] = d['affinity_groups'] if d['affinity_groups']
        # Add credentials
        node[:credentials] = Hash[d['credentials'].map { |k, v| [k.to_sym, v] }] unless d['credentials'].nil?
        # Add DNS
        node[:dns] = Hash[d['dns'].map { |k, v| [k.to_sym, v] }] unless d['dns'].nil?
        @nodes << node
      end
    end

    def execute
      @nodes.each { |node| Infrastructure::bootstrap(node, @disk_db) }
    end

    private

    def validate
      Dopv::log.debug("Plan: #{__method__}: Validating.")
      # A plan must be of a Hash type and it must have at least clouds and nodes
      # definitions.
      raise Errors::PlanError, "#{__method__}: The plan must be a Hash" unless @plan.is_a?(Hash)
      if !@plan.has_key?('infrastructures') || !@plan.has_key?('nodes')
        raise Errors::PlanError, "#{__method__}: Infrastructures and nodes must be defined"
      end
      # Infrastructure and node definitions must be groupped into hashes.
      if !@plan['infrastructures'].is_a?(Hash) || !@plan['nodes'].is_a?(Hash)
        raise Errors::PlanError, "#{__method__}: Infrastructures and nodes must be Hash"
      end
      @plan['infrastructures'].each do |i, d|
        raise Errors::PlanError, "#{__method__}: Infrastructure #{i}: Unsupported type" unless Infrastructure.supported?(d)
        raise Errors::PlanError, "#{__method__}: Infrastructure #{i}: Networks definition missing" unless d.has_key?('networks')
        d['networks'].each_value do |v|
          error_msg = "#{__method__}: Infrastructure #{i}: Invalid network definition"
          case v
          when nil # No IP configuration
            Dopv::log.warn("Plan: #{__method__}: No IP parameters specified")
          when Hash # With IP configuration
            if !v['ip_pool'].is_a?(Hash) || !v['ip_pool']['from'].is_a?(String) ||
               !v['ip_pool']['to'].is_a?(String) || !v['ip_netmask'].is_a?(String)
              raise Errors::PlanError, error_msg
            end
            begin
              IPAddr.new(v['ip_netmask'])
              ip_from   = IPAddr.new(v['ip_pool']['from'])
              ip_to     = IPAddr.new(v['ip_pool']['to'])
              ip_defgw  = IPAddr.new(v['ip_defgw']) if v['ip_defgw']
              if ip_from > ip_to || !(ip_defgw < ip_from || ip_defgw > ip_to)
                raise Errors::PlanError, error_msg
              end
            rescue
              raise Errors::PlanError, error_msg
            end
          else
            raise Errors::PlanError, error_msg
          end
        end
      end
      # A node definition must be defined in nodes hash and it is be referenced
      # by its name.
      # The node definition itself must be of a Hash type and it must contain
      # at least definitions of the infrastructure, image, network.
      # Again, these must be of a certain type.
      # An infrastructure definition pointed to by node's 'infrastructure' key
      # must exist in infrastructures section of the @plan.
      @plan['nodes'].each do |n, d|
        error_msg = "#{__method__}: Node #{n}: Invalid node definition"
        if !(d.is_a?(Hash) && d['infrastructure'].is_a?(String) &&
             d['image'].is_a?(String) && d['interfaces'].is_a?(Hash))
          raise Errors::PlanError, error_msg 
        end
        raise Errors::PlanError, error_msg if d['full_clone'] && d['full_clone'] != true && d['full_clone'] != false
        raise Errors::PlanError, error_msg if d['product_id'] && !d['product_id'].is_a?(String)
        raise Errors::PlanError, error_msg if d['organization_name'] && !d['organization_name'].is_a?(String)
        raise Errors::PlanError, error_msg if d['timezone'] && d['timezone'].to_s !~ /^\d{3}$/
        # If flavor is defined, check if flavor it is a simple string.
        raise Errors::PlanError, error_msg if d['flavor'] && !d['flavor'].is_a?(String)
        # If cpu is defined, check if it is a simple integer number.
        raise Errors::PlanError, error_msg if d['cores'] && (!d['cores'].is_a?(Integer) || !(d['cores'] > 0))
        # If memory is defined, check if it is a simple string of a certain
        # format.
        raise Errors::PlanError, error_msg if d['memory'] && d['memory'].to_s !~ /^\d+[\dmMgG]$/
        # If memory is defined, check if it is a simple string of a certain
        # format.
        raise Errors::PlanError, error_msg if d['storage'] && d['storage'].to_s !~ /^\d+[\dmMgG]$/
        
        raise Errors::PlanError, "#{__method__}: Node #{n}: Invalid infrastructure pointer" unless @plan['infrastructures'].has_key?(d['infrastructure'])
        if d.has_key?('infrastructure_properties')
          error_msg = "#{__method__}: Node #{n}: Invalid infrastructure properties definition"
          if !d['infrastructure_properties'].is_a?(Hash)
            raise Errors::PlanError, error_msg
          end
          d['infrastructure_properties'].each do |p, v|
            case p
            when 'datacenter'
              raise Errors::PlanError, error_msg unless v.is_a?(String)
            when 'cluster'
              raise Errors::PlanError, error_msg unless v.is_a?(String)
            when 'keep_ha'
              if v != true && v != false
                raise Errors::PlanError, error_msg
              end
            when 'affinity_groups'
              raise Errors::PlanError, error_msg unless v.is_a?(Array)
            when 'dest_folder'
              raise Errors::PlanError, error_msg unless v.is_a?(String)
            when 'default_pool'
              raise Errors::PlanError, error_msg unless v.is_a?(String)
            else
              raise Errors::PlanError, error_msg
            end
          end
        end

        # Networks
        d['interfaces'].each do |i, v|
          if !v.is_a?(Hash) || !v['network'].is_a?(String)
            raise Errors::PlanError, "#{__method__}: Node #{n}: Invalid interface definition"
          end
          if v['virtual_switch'] && !v['virtual_switch'].is_a?(String)
            raise Errors::PlanError,  "#{__method__}: Node #{n}: Invalid virtual switch definition"
          end
          unless @plan['infrastructures'][d['infrastructure']]['networks'].has_key?(v['network'])
            raise Errors::PlanError, "#{__method__}: Node #{n}: Invalid network pointer"
          end
          if v['ip'] && v['ip'] != "dhcp" && v['ip'] != "none"
            error_msg = "#{__method__}: Node #{n}: Invalid IP definition"
            begin
              ip = IPAddr.new(v['ip'])
              ip_from   = IPAddr.new(@plan['infrastructures'][d['infrastructure']]['networks'][v['network']]['ip_pool']['from'])
              ip_to     = IPAddr.new(@plan['infrastructures'][d['infrastructure']]['networks'][v['network']]['ip_pool']['to'])
              ip_defgw  = IPAddr.new(@plan['infrastructures'][d['infrastructure']]['networks'][v['network']]['ip_defgw'] || '0.0.0.0')
            rescue
              raise Errors::PlanError, error_msg
            end
            if ip < ip_from || ip > ip_to || ip == ip_defgw
              raise Errors::PlanError, error_msg
            end
            if v['set_gateway'] && (v['set_gateway'] != true && v['set_gateway'] != false)
              raise Errors::PlanError, "#{__method__}: Node #{n}: set_gateway must be of boolean type"
            end
          end
        end

        # Disks
        if d.has_key?('disks')
          raise Errors::PlanError, "#{__method__}: Node #{n}: Invalid disk definition" unless d['disks'].is_a?(Array)
          d['disks'].each do |dsk|
            if !dsk.is_a?(Hash) || !dsk['name'].is_a?(String) ||
               (!dsk['pool'].is_a?(String) &&
                !d['infrastructure_properties']['default_pool'].is_a?(String)
               ) || !dsk['size'].is_a?(String) || dsk['size'] !~ /[1-9]*[MGTmgt]/
              raise Errors::PlanError, "#{__method__}: Node #{n}: Invalid disk name, pool or size definition"
            end
          end
        end

        # Credentials
        if d.has_key?('credentials')
          if ! d['credentials'].is_a?(Hash)
              raise Errors::PlanError, "#{__method__}: Node #{n}: Invalid credentials specification"
          end
          if d['credentials'].has_key?('root_password') && !d['credentials']['root_password'].is_a?(String)
              raise Errors::PlanError, "#{__method__}: Node #{n}: Invalid root password definition"
          end
          if d['credentials'].has_key?('root_ssh_keys') && !d['credentials']['root_ssh_keys'].is_a?(Array)
              raise Errors::PlanError, "#{__method__}: Node #{n}: Invalid root ssh keys definition"
          end
          if d['credentials'].has_key?('administrator_fullname') && !d['credentials']['administrator_fullname'].is_a?(String)
              raise Errors::PlanError, "#{__method__}: Node #{n}: Invalid administrator full name definition"
          end
          if d['credentials'].has_key?('administrator_password') && !d['credentials']['administrator_password'].is_a?(String)
              raise Errors::PlanError, "#{__method__}: Node #{n}: Invalid administrator password definition"
          end
        end
        # DNS
        if d.has_key?('dns')
          if !d['dns'].is_a?(Hash) || !d['dns']['nameserver'].is_a?(Array)
            raise Errors::PlanError, "#{__method__}: Node #{n}: Invalid DNS specification"
          end
          d['dns']['nameserver'].each do |srv|
            begin
              IPAddr.new(srv)
            rescue
              raise Errors::PlanError, "#{__method__}: Node #{n}: Invalid name server definition"
            end
          end
          if d['dns'].has_key?('domain') && !d['dns']['domain']
            raise Errors::PlanError, "#{__method__}: Node #{n}: Invalid search domain definition"
          end
        end
      end
    end
  end
end
