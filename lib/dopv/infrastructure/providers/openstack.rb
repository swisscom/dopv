require 'fog'

module Dopv
  module Infrastructure
    class OpenStack < Base
      extend Forwardable

      def_delegator :@plan, :flavor, :flavor_name

      def initialize(node_config, data_disks_db)
        super(node_config, data_disks_db)


        @compute_connection_opts = {
          :provider                => 'openstack',
          :openstack_username      => provider_username,
          :openstack_api_key       => provider_password,
          :openstack_project_name  => provider_tenant,
          :openstack_domain_id     => provider_domain_id,
          :openstack_auth_url      => provider_url,
          :openstack_endpoint_type => provider_endpoint_type,
          :connection_options      => {
            :ssl_verify_peer => false,
            #:debug_request   => true
          }
        }

        @network_connection_opts = @compute_connection_opts
        @volume_connection_opts  = @compute_connection_opts

        @node_creation_opts = {
          :name            => nodename,
          :image_ref       => template.id,
          :flavor_ref      => flavor.id,
          :config_drive    => use_config_drive?,
          :security_groups => security_groups
        }
      end

      private

      def provider_tenant
        @provider_tenant ||= infrastructure_properties.tenant
      end

      def provider_domain_id
        @provider_domain_id ||= infrastructure_properties.domain_id
      end

      def provider_endpoint_type
        @provider_endpoint_type ||= infrastructure_properties.endpoint_type
      end

      def use_config_drive?
        @use_config_drive ||= infrastructure_properties.use_config_drive?
      end

      def security_groups
        @security_groups ||= infrastructure_properties.security_groups
      end

      def network_provider
        Dopv::log.info("Node #{nodename}: Creating network provider.") unless @network_provider
        @network_provider ||= @network_connection_opts ? ::Fog::Network.new(@network_connection_opts) : nil
      end

      def flavor(filters={})
        @flavor ||= compute_provider.flavors(filters).find { |f| f.name == flavor_name }
        raise ProviderError, "No such flavor #{flavor_name}" unless @flavor
        @flavor
      end

      def network(name, filters={})
        net = network_provider.networks(filters).find { |n| n.name == name || n.id == name }
        raise ProviderError, "No such network #{name}" unless net
        net
      end

      def subnet(name, filters={})
        net = network_provider.subnets(filters).find { |s| s.name == name || s.id == name }
        raise ProviderError, "No such subnetwork #{name}" unless net
        net
      end

      def assign_security_groups(node_instance)
        unless security_groups.empty?
          Dopv::log.info("Node #{nodename}: Assigning security groups.")
          config_sgs = security_groups.dup
          node_instance.security_groups.uniq { |g| g.id }.each do |sg|
            # Remove the security group from configuration if it is already
            # assigned to an instance.
            if config_sgs.delete(sg.name)
              Dopv::log.debug("Node #{nodename}: Already assigned to security group #{sg.name}.")
              next
            end
            # Remove the security group assignment if it isn't in the
            # configuration.
            unless config_sgs.include?(sg.name)
              Dopv::log.debug("Node #{nodename}: Removing unneeded security group #{sg.name}.")
              compute_provider.remove_security_group(node_instance.id, sg.name)
              wait_for_task_completion(node_instance)
            end
          end
          # Add remaining security groups defined in config array.
          config_sgs.each do |sg_name|
            begin
              Dopv::log.debug("Node #{nodename}: Adding security group #{sg_name}.")
              compute_provider.add_security_group(node_instance.id, sg_name)
              wait_for_task_completion(node_instance)
            rescue
              raise ProviderError, "An error occured while assigning security group #{sg_name}"
            end
          end
          node_instance.reload
        end
        node_instance.security_groups
      end

      def node_instance_stopped?(node_instance)
        !node_instance.ready?
      end

      def wait_for_task_completion(node_instance)
        node_instance.wait_for { ready? }
      end

      def create_node_instance
        Dopv::log.info("Node #{nodename}: Creating node instance.")

        @node_creation_opts[:nics] = add_node_network_ports
        @node_creation_opts[:user_data_encoded] = [cloud_config].pack('m')

        Dopv::log.debug("Node #{nodename}: Spawning node instance.")
        instance = compute_provider.servers.create(@node_creation_opts)
        wait_for_task_completion(instance)
        instance.reload

        assign_security_groups(instance)

        instance
      end

      def destroy_node_instance(node_instance, destroy_data_volumes=false)
        remove_node_floating_ips(node_instance)
        remove_node_network_ports(node_instance)
        super(node_instance, destroy_data_volumes)
      end

      def start_node_instance(node_instance)
      end

      def stop_node_instance(node_instance)
        super(node_instance)
        node_instance.wait_for { !ready? }
      end

      def add_node_volume(node_instance, config)
        volume = super(
          compute_provider, {
            :name => config.name,
            :display_name => config.name,
            :size => config.size.gibibytes.to_i,
            :volume_type => config.pool,
            :description => config.name
          }
        )
        volume.wait_for { ready? }
        attach_node_volume(node_instance, volume.reload)
        volume.reload
      end

      def destroy_node_volume(node_instance, volume)
        volume_instance = detach_node_volume(node_instance, volume)
        volume_instance.destroy
        node_instance.volumes.all({}).reload
      end

      def attach_node_volume(node_instance, volume)
        volume_instance = node_instance.volumes.all({}).find { |v| v.id = volume.id }
        node_instance.attach_volume(volume_instance.id, nil)
        volume_instance.wait_for { volume_instance.status.downcase == "in-use" }
        volume_instance
      end

      def detach_node_volume(node_instance, volume)
        volume_instance = node_instance.volumes.all({}).find { |v| v.id = volume.id }
        node_instance.detach_volume(volume_instance.id)
        volume_instance.wait_for { volume_instance.status.downcase == "available" }
        volume_instance
      end

      def record_node_data_volume(volume)
        super(
          :name => volume.name,
          :id   => volume.id,
          :pool => volume.type == 'None' ? nil : volume.type,
          :size => volume.size * 1073741824 # Returned in gibibytes
        )
      end

      def fixed_ip(subnet_id, ip_address)
        rval = { :subnet_id => subnet_id }
        [:dhcp, :none].include?(ip_address) ? rval : rval.merge(:ip_address => ip_address)
      end

      def add_node_network_port(attrs)
        ::Dopv::log.debug("Node #{nodename}: Adding network port #{attrs[:name]}.")
        network_provider.ports.create(attrs)
      end

      def add_node_network_ports
        ::Dopv::log.info("Node #{nodename}: Adding network ports.")
        ports_config = {}
        interfaces_config.each do |i|
          s = subnet(i.network)
          port_name = "#{nodename}_#{s.network_id}"
          if ports_config.has_key?(port_name)
              ports_config[port_name][:fixed_ips] << fixed_ip(s.id, i.ip)
          else
            ports_config[port_name] = {
              :network_id => s.network_id,
              :fixed_ips => [fixed_ip(s.id, i.ip)]
            }
          end
        end
        @network_ports = ports_config.map { |k,v| add_node_network_port(v.merge(:name => k)) }
        @network_ports.collect { |p| {:net_id => p.network_id, :port_id => p.id} } # Net ID is required in Liberty++
      end

      def remove_node_network_ports(node_instance)
        ::Dopv::log.warn("Node #{nodename}: Removing network ports.")
        @network_ports ||= network_provider.ports.select { |p| p.device_id == node_instance.id } rescue {}
        @network_ports.each { |p| p.destroy rescue nil } # TODO: dangerous, rewrite
        @network_ports = {}
      end

      def add_node_floating_ip(attrs)
        ::Dopv::log.debug("Node #{nodename}: Adding floating IP to #{attrs[:nicname]}.")
        network_provider.floating_ips.create(attrs)
      end

      def add_node_floating_ips(node_instance)
        ::Dopv::log.info("Node #{nodename}: Adding floating IPs.")
        @network_ports ||= network_provider.ports.select { |p| p.device_id == node_instance.id }
        interfaces_config.each do |i|
          if i.floating_network
            floating_network = network(i.floating_network)
            subnetwork = subnet(i.network)
            port = @network_ports.find { |p| p.fixed_ips.find { |f| f["subnet_id"] == subnetwork.id } }
            attrs = {
              :floating_network_id => floating_network.id,
              :port_id => port.id,
              :fixed_ip_address => port.fixed_ips.first["ip_address"],
              :nicname => i.name
            }
            add_node_floating_ip(attrs)
          end
        end
      end
      alias_method :add_node_nics, :add_node_floating_ips

      def remove_node_floating_ips(node_instance)
        ::Dopv::log.warn("Node #{nodename}: Removing floating IPs.")
        if node_instance
          floating_ips = network_provider.floating_ips.select do |f|
            node_instance.floating_ip_addresses.include?(f.floating_ip_address)
          end
          floating_ips.each { |f| f.destroy rescue nil } # TODO: dangerous, rewrite
        end
      end
      alias_method :remove_node_nics, :remove_node_floating_ips

      def cloud_config
        config = "#cloud-config\n"        \
          "hostname: #{hostname}\n"       \
          "fqdn: #{fqdn}\n"               \
          "manage_etc_hosts: True\n"      \
          "ssh_pwauth: True\n"

        if root_password
          config <<                       \
            "chpasswd:\n"                 \
            "  list: |\n"                 \
            "    root:#{root_password}\n" \
            "  expire: False\n"
        end

        unless root_ssh_pubkeys.empty?
          config <<                       \
            "users:\n"                    \
            "  - name: root\n"            \
            "    ssh_authorized_keys:\n"
          root_ssh_pubkeys.each { |k| config << "      - #{k}\n" }
        end

        config <<
          "runcmd:\n" \
          "  - service network restart\n"

        config
      end

      def get_node_ip_addresses(node_instance)
        (node_instance.ip_addresses + [node_instance.floating_ip_address]).flatten.uniq
      end
    end
  end
end
