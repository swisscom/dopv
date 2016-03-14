require 'yaml'
require 'ipaddr'

module Dopv
  class PlanError < StandardError
    def exit_code; 1; end
  end

  class Plan
    def initialize(plan)
      @nodes = []
      @plan ||= load_plan(plan)
    end

    def parse
      validate

      # Generate node definition according to plan
      Dopv::log.debug("Parsing.")
      infrastructures = @plan['infrastructures']
      credentials = @plan['credentials']
      @plan['nodes'].each do |n, d|
        node = {}
        # Infrastructure provider definitions
        node[:provider] = infrastructures[d['infrastructure']]['type'].to_sym
        node[:provider_endpoint] = infrastructures[d['infrastructure']]['endpoint'] rescue nil
        # Credentials definitions
        case infrastructures[d['infrastructure']]['credentials']
        when Hash
          node[:provider_username] = infrastructures[d['infrastructure']]['credentials']['username'] rescue nil
          node[:provider_password] = infrastructures[d['infrastructure']]['credentials']['password'] rescue nil
          node[:provider_pubkey_hash] = infrastructures[d['infrastructure']]['credentials']['provider_pubkey_hash'] rescue nil
        when String
          node[:provider_username] = credentials[infrastructures[d['infrastructure']]['credentials']]['username'] rescue nil
          node[:provider_password] = credentials[infrastructures[d['infrastructure']]['credentials']]['password'] rescue nil
        end
        # Node definitions
        node[:nodename] = n
        node[:fqdn] = d['fqdn']
        node[:image] = d['image']
        node[:flavor] = d['flavor']
        node[:cores] = d['cores']
        node[:memory] = d['memory']
        node[:storage] = d['storage']
        node[:full_clone] = d['full_clone']
        node[:product_id] = d['product_id']
        node[:organization_name] = d['organization_name']
        node[:use_config_drive] = [false, 'false'].include?(d['infrastructure_properties']['use_config_drive']) ? false : true
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
        if d['interfaces']
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
            interface[:floating_network] = v['floating_network']
            (node[:interfaces] ||= []) << interface
          end
        end
        # Add affinity groups
        node[:affinity_groups] = d['affinity_groups'] if d['affinity_groups']
        # Add credentials
        node[:credentials] = Hash[d['credentials'].map { |k, v| [k.to_sym, v] }] unless d['credentials'].nil?
        # Add DNS
        node[:dns] = Hash[d['dns'].map { |k, v| [k.to_sym, v] }] unless d['dns'].nil?
        @nodes << node
      end

      @nodes
    end

    private

    def load_plan(plan)
      ::Dopv::log.info("Loading deployment plan.")
      case plan
      when String
        YAML.load_file(plan)
      when Hash
        plan
      else
        raise PlanError, "The plan must be a file name or a hash"
      end
    end

    def validate
      Dopv::log.debug("Validating.")
      # A plan must be of a Hash type and it must have at least clouds and nodes
      # definitions.
      raise PlanError, "The plan must be a Hash" unless @plan.is_a?(Hash)
      raise PlanError, "Infrastructures and nodes hashes must be defined" unless
        %w(infrastructures nodes).all? { |k| @plan.key?(k) && @plan[k].is_a?(Hash) }

      if @plan.has_key?('credentials')
        raise PlanError, "Credentials must be a hash" unless @plan['credentials'].is_a?(Hash)
      else
        Dopv::log.warn("Credentials will be required in DOPv >= 0.4.0")
      end

      @plan['infrastructures'].each do |i, d|
        raise PlanError, "Infrastructure #{i}: Unsupported type #{d['type'].to_s}" unless ::Dopv::Infrastructure::supported_provider?(d)

        case d['credentials']
        when String
          raise PlanError, "Infrastructure #{i}: No such credentials #{d['credentials']}" unless @plan['credentials'].has_key?(d['credentials'])
        when Hash
          Dopv::log.warn("Infrastructure #{i}: Explicit credentials definition is deprecated and will be removed in DOPv >= 0.4.0")
          raise PlanError, "Infrastructure #{i}: Invalid credentials definition" unless
            %w(username password).all? { |k| d['credentials'].key?(k) && d['credentials'][k].is_a?(String) }
        end

        next if d['type'] == 'baremetal' && !d.key?('networks')
        raise PlanError, "Infrastructure #{i}: Networks definition missing" unless d.has_key?('networks')
        d['networks'].each do |n, v|
          name = n.to_s

          if v.nil?
            Dopv::log.warn("Infrastructure #{i}: Network '#{name}' must be a hash. This will become a strict rule in DOPv >= 0.4.0")
            v = {}
          end

          raise PlanError, "Infrastructure #{i}: Network '#{name}' must be a hash" unless v.is_a?(Hash)
          unless v.empty?
            raise PlanError, "Infrastructure #{i}: A non-empty network '#{name}' must specify 'ip_pool', 'ip_netmask' and 'ip_defgw'" unless
              v.keys.sort == %w(ip_defgw ip_netmask ip_pool)
            raise PlanError, "Infrastructure #{i}: The 'ip_pool' of network '#{name}' must be a hash that consists of 'from' and 'to' keys" unless
              v['ip_pool'].is_a?(Hash) && v['ip_pool'].keys == %w(from to)
            raise PlanError, "Infrastructure #{i}: The values of 'from' and 'to' keys of network '#{name}' must be strings" unless
              v['ip_pool']['from'].is_a?(String) && v['ip_pool']['to'].is_a?(String)
            raise PlanError, "Infrastructure #{i}: The 'ip_netmask' and 'ip_gateway' of network '#{name}' must be strings" unless
              v['ip_netmask'].is_a?(String) && v['ip_defgw'].is_a?(String)
            begin
              IPAddr.new(v['ip_netmask'])
              ip_from   = IPAddr.new(v['ip_pool']['from'])
              ip_to     = IPAddr.new(v['ip_pool']['to'])
              ip_defgw  = IPAddr.new(v['ip_defgw']) if v['ip_defgw']
              if ip_from > ip_to || !(ip_defgw < ip_from || ip_defgw > ip_to)
                raise PlanError, "Infrastructure #{i}: 'from' must be smaller than 'to' and 'ip_gateway' must be outside of 'from' to 'to' interval"
              end
            rescue
              raise PlanError, "Infrastructure #{i}: Invalid definition of one or more values of network '#{name}'"
            end
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
        error_msg = "Node #{n}: Invalid node definition"
        if !(d.is_a?(Hash) && d['infrastructure'].is_a?(String))
          raise PlanError, error_msg
        end
        raise PlanError, error_msg if d['full_clone'] && d['full_clone'] != true && d['full_clone'] != false
        raise PlanError, error_msg if d['product_id'] && !d['product_id'].is_a?(String)
        raise PlanError, error_msg if d['organization_name'] && !d['organization_name'].is_a?(String)
        raise PlanError, error_msg if d['timezone'] && d['timezone'].to_s !~ /^\d{3}$/
        # If flavor is defined, check if flavor it is a simple string.
        raise PlanError, error_msg if d['flavor'] && !d['flavor'].is_a?(String)
        # If cpu is defined, check if it is a simple integer number.
        raise PlanError, error_msg if d['cores'] && (!d['cores'].is_a?(Integer) || !(d['cores'] > 0))
        # If memory is defined, check if it is a simple string of a certain
        # format.
        raise PlanError, error_msg if d['memory'] && d['memory'].to_s !~ /^\d+[\dmMgG]$/
        # If memory is defined, check if it is a simple string of a certain
        # format.
        raise PlanError, error_msg if d['storage'] && d['storage'].to_s !~ /^\d+[\dmMgG]$/

        raise PlanError, "Node #{n}: Invalid infrastructure pointer #{d['infrastructure']}" unless @plan['infrastructures'].has_key?(d['infrastructure'])
        if d.has_key?('infrastructure_properties')
          error_msg = "Node #{n}: Invalid infrastructure properties definition"
          if !d['infrastructure_properties'].is_a?(Hash)
            raise PlanError, error_msg
          end
          d['infrastructure_properties'].each do |p, v|
            case p
            when 'datacenter'
              raise PlanError, error_msg unless v.is_a?(String)
            when 'cluster'
              raise PlanError, error_msg unless v.is_a?(String)
            when 'keep_ha'
              if v != true && v != false
                raise PlanError, error_msg
              end
            when 'affinity_groups'
              raise PlanError, error_msg unless v.is_a?(Array)
            when 'dest_folder'
              raise PlanError, error_msg unless v.is_a?(String)
            when 'default_pool'
              raise PlanError, error_msg unless v.is_a?(String)
            when 'tenant'
              raise PlanError, error_msg unless v.is_a?(String)
            when 'tenant_id'
              raise PlanError, error_msg unless v.is_a?(String)
            when 'use_config_drive'
              raise PlanError, error_msg unless [true, false, 'true', 'false'].include?(v)
            else
              raise PlanError, error_msg
            end
          end
        end

        # Networks
        if d.has_key?('interfaces')
          raise PlanError, "Node #{n}: Interfaces definition must be a hash" unless d['interfaces'].is_a?(Hash)
          d['interfaces'].each do |i, v|
            name = i.to_s
            if !v.is_a?(Hash) || !v['network'].is_a?(String)
              raise PlanError, "Node #{n}: Invalid definition of interface #{name}"
            end
            if v['virtual_switch'] && !v['virtual_switch'].is_a?(String)
              raise PlanError,  "Node #{n}: Invalid virtual switch definition of interface #{name}"
            end
            unless @plan['infrastructures'][d['infrastructure']]['networks'].has_key?(v['network'])
              raise PlanError, "Node #{n}: Invalid network pointer #{v['network']} of interface #{name}"
            end

            Dopv::log.warn("Node #{n}: Interface #{name} must have a valid IP definition (IP, dhcp or none). This will become a strict rule in DOPv >= 0.4.0") if v['ip'].nil?
            if v['ip'] && v['ip'] != "dhcp" && v['ip'] != "none"
              error_msg = "Node #{n}: Interface #{name} has an invalid IP definition (can be a valid IP, dhcp or none)"
              begin
                ip = IPAddr.new(v['ip'])
                ip_from   = IPAddr.new(@plan['infrastructures'][d['infrastructure']]['networks'][v['network']]['ip_pool']['from'])
                ip_to     = IPAddr.new(@plan['infrastructures'][d['infrastructure']]['networks'][v['network']]['ip_pool']['to'])
                ip_defgw  = IPAddr.new(@plan['infrastructures'][d['infrastructure']]['networks'][v['network']]['ip_defgw'] || '0.0.0.0')
              rescue
                raise PlanError, error_msg
              end
              if ip < ip_from || ip > ip_to || ip == ip_defgw
                raise PlanError, error_msg
              end
              if v['set_gateway'] && (v['set_gateway'] != true && v['set_gateway'] != false)
                raise PlanError, "Node #{n}: set_gateway of interface #{name} must be of boolean type"
              end
            end
          end
        end

        # Disks
        if d.has_key?('disks')
          raise PlanError, "Node #{n}: Invalid disk definition" unless d['disks'].is_a?(Array)
          d['disks'].each do |dsk|
            if !dsk.is_a?(Hash) || !dsk['name'].is_a?(String) ||
               (!(dsk['pool'].is_a?(String) || dsk['pool'].nil?) &&
                !d['infrastructure_properties']['default_pool'].is_a?(String)
               ) || !dsk['size'].is_a?(String) || dsk['size'] !~ /[1-9]*[MGTmgt]/
              raise PlanError, "Node #{n}: Invalid disk name, pool or size definition"
            end
          end
        end

        # Credentials
        if d.has_key?('credentials')
          if ! d['credentials'].is_a?(Hash)
              raise PlanError, "Node #{n}: Invalid credentials specification"
          end
          if d['credentials'].has_key?('root_password') && !d['credentials']['root_password'].is_a?(String)
              raise PlanError, "Node #{n}: Invalid root password definition"
          end
          if d['credentials'].has_key?('root_ssh_keys') && !d['credentials']['root_ssh_keys'].is_a?(Array)
              raise PlanError, "Node #{n}: Invalid root ssh keys definition"
          end
          if d['credentials'].has_key?('administrator_fullname') && !d['credentials']['administrator_fullname'].is_a?(String)
              raise PlanError, "Node #{n}: Invalid administrator full name definition"
          end
          if d['credentials'].has_key?('administrator_password') && !d['credentials']['administrator_password'].is_a?(String)
              raise PlanError, "Node #{n}: Invalid administrator password definition"
          end
        end
        # DNS
        if d.has_key?('dns')
          if !d['dns'].is_a?(Hash) || !d['dns']['nameserver'].is_a?(Array)
            raise PlanError, "Node #{n}: Invalid DNS specification"
          end
          d['dns']['nameserver'].each do |srv|
            begin
              IPAddr.new(srv)
            rescue
              raise PlanError, "Node #{n}: Invalid name server definition"
            end
          end
          if d['dns'].has_key?('domain') && !d['dns']['domain']
            raise PlanError, "Node #{n}: Invalid search domain definition"
          end
        end
      end
    end
  end
end
