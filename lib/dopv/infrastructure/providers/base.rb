require 'forwardable'
require 'uri'
require 'fog'
require 'open3'
require 'dop_common/utils'

module Dopv
  module Infrastructure
    class ProviderError < StandardError
      def exit_code
        4
      end
    end

    class Base
      extend Forwardable
      include DopCommon::Utils

      MAX_RETRIES = 5

      attr_reader :data_disks_db
      def_delegators :@plan, :nodename, :fqdn, :hostname, :domainname, :dns
      def_delegators :@plan, :timezone
      def_delegators :@plan, :full_clone?, :image, :cores, :memory, :storage, :flavor
      def_delegators :@plan, :infrastructure, :infrastructure_properties
      def_delegator :@plan, :interfaces, :interfaces_config
      def_delegator :@plan, :data_disks, :volumes_config
      def_delegators :@plan, :credentials
      def_delegators :@plan, :hooks

      def self.bootstrap_node(plan, state_store)
        new(plan, state_store).bootstrap_node
      end

      def self.destroy_node(plan, state_store, destroy_data_volumes=false)
        new(plan, state_store).destroy_node(destroy_data_volumes)
      end

      def initialize(plan, state_store)
        @compute_provider = nil
        @plan = plan
        @data_disks_db = Dopv::PersistentDisk::DB.new(state_store, nodename)
      end

      def bootstrap_node
        begin
          unless get_node_instance
            execute_hook(:pre_create_vm, true)
            node_instance = create_node_instance
            add_node_nics(node_instance)
            add_node_data_volumes(node_instance)
            add_node_affinities(node_instance)
            start_node_instance(node_instance)
            execute_hook(:post_create_vm, true)
          else
            ::Dopv::log.warn("Node #{nodename}: Already exists.")
            # TODO: Ask Marcel what would be a purpose/use case of this
            execute_hook(:pre_create_vm, false)
            execute_hook(:post_create_vm, false)
          end
        rescue Exception => e
          ::Dopv::log.error("Node #{nodename}: #{e}")
          destroy_node_instance(node_instance)
          raise ProviderError, "Node #{nodename}: #{e}."
        end
      end

      def destroy_node(destroy_data_volumes=false)
        node_instance = get_node_instance
        if node_instance
          execute_hook(:pre_destroy_vm, true)
          destroy_node_instance(node_instance, destroy_data_volumes)
          execute_hook(:post_destroy_vm, true)
        else
          # TODO: Ask Marcel what would be a purpose/use case of this
          execute_hook(:pre_destroy_vm, false)
          execute_hook(:post_destroy_vm, false)
        end
      end

      private

      def provider_username
        @provider_username ||= infrastructure.credentials.username
      end

      def provider_password
        @provider_passowrd ||= infrastructure.credentials.password
      end

      def provider_url
        @provider_url ||= infrastructure.endpoint.to_s
      end

      def provider_host
        @provider_host ||= infrastructure.endpoint.host
      end

      def provider_port
        @provider_port ||= infrastructure.endpoint.port
      end

      def provider_scheme
        @provider_scheme ||= infrastructure.endpoint.scheme
      end

      def provider_ssl?
        provider_scheme == 'https'
      end

      def root_password
        cred = credentials.find { |c| c.type == :username_password && c.username == 'root' } if
          @root_password.nil?
        @root_password ||= cred.nil? ? nil : cred.password
      end

      def root_ssh_pubkeys
        cred = credentials.find_all { |c| c.type == :ssh_key && c.username == 'root' } if
          @root_ssh_pubkeys.nil?
        @root_ssh_pubkey ||= cred.empty? ? [] : cred.collect { |k| k.public_key }.uniq
      end

      def administrator_password
        cred = credentials.find { |c| c.type == :username_password && c.username == 'Administrator' } if
          @administrator_password.nil?
        @administrator_password ||= cred.nil? ? nil : cred.password
      end

      def administrator_fullname
        'Administrator'
      end

      def keep_ha?
        @keep_ha ||= infrastructure_properties.keep_ha?
      end

      def compute_provider
        Dopv::log.info("Node #{nodename}: Creating compute provider.") unless @compute_provider
        @compute_provider ||= @compute_connection_opts ? ::Fog::Compute.new(@compute_connection_opts) : nil
      end

      def datacenter(filters={})
        @datacenter ||= compute_provider.datacenters(filters).find do |d|
          if d.is_a?(Hash) && d.has_key?(:name)
            d[:name] == infrastructure_properties.datacenter
          elsif d.respond_to?(:name)
            d.name == infrastructure_properties.datacenter
          else
            raise ProviderError, "Unsupported datacenter class #{d.class}"
          end
        end
        raise ProviderError, "No such data center #{infrastructure_properties.datacenter}" unless @datacenter
        @datacenter
      end

      def cluster(filters={})
        @cluster ||= compute_provider.clusters(filters).find { |c| c.name == infrastructure_properties.cluster }
        raise ProviderError, "No such cluster #{infrastructure_properties.cluster}" unless @cluster
        @cluster
      end

      def template(filters={})
        raise ProviderError, "No template defined" unless image
        @template ||= if compute_provider.respond_to?(:templates)
                         compute_provider.templates.all(filters).find { |t| t.name == image }
                       elsif compute_provider.respond_to?(:images)
                         compute_provider.images.all(filters).find { |t| t.name == image }
                       else
                         raise ProviderError, "The provider does not to have template/image collection"
                       end
        raise ProviderError, "No such template #{image}" unless @template
        @template
      end

      def get_node_instance(filters = {})
        retries = 0
        compute_provider.servers.all(filters).find { |n| n.name == nodename }
      rescue => e
        errmsg = "Node #{nodename}: An error occured while searching for a node: #{e}."
        retries += 1
        if retries <= MAX_RETRIES
          Dopv.log.warn("#{errmsg} Retrying (##{retries}).")
          sleep 1
          retry
        else
          raise ProviderError, "#{errmsg}. Bailing out"
        end
      end

      def node_instance_ready?(node_instance)
        node_instance.ready?
      end

      def node_instance_stopped?(node_instance)
        node_instance.stopped?
      end

      def wait_for_task_completion(node_instance)
      end

      def create_node_instance
        Dopv::log.info("Node #{nodename}: Creating node instance.")
        node_instance = compute_provider.servers.create(@node_creation_opts)
        wait_for_task_completion(node_instance)
        node_instance
      end

      def destroy_node_instance(node_instance, destroy_data_volumes=false)
        if node_instance
          stop_node_instance(node_instance)

          volumes = data_disks_db.volumes
          volumes.each do |v|
            if destroy_data_volumes
              ::Dopv::log.warn("Node #{nodename} Destroying data volume #{v.name}.")
              begin
                destroy_node_volume(node_instance, v)
              rescue
                ::Dopv::log.error("Could not destroy data volume #{v.name}. Please fix manually.")
              end
              erase_node_data_volume(v)
            else
              ::Dopv::log.debug("Node #{nodename} Detaching data volume #{v.name}.")
              begin
                detach_node_volume(node_instance, v)
              rescue
                ::Dopv::log.warn("Could not detach data volume #{v.name}.")
              end
            end
          end

          ::Dopv::log.warn("Node #{nodename}: Destroying node.")
          node_instance.destroy rescue nil
        end
      end

      def reload_node_instance(node_instance)
        node_instance.reload
      end

      def customize_node_instance(node_instance)
      end

      def start_node_instance(node_instance)
        stop_node_instance(node_instance)
        ::Dopv::log.info("Node #{nodename}: Starting node.")
        customize_node_instance(node_instance)
      end

      def stop_node_instance(node_instance)
        reload_node_instance(node_instance)
        unless node_instance_stopped?(node_instance)
          ::Dopv::log.info("Node #{nodename}: Stopping node.")
          wait_for_task_completion(node_instance)
          node_instance.stop
          reload_node_instance(node_instance)
        end
      end

      def add_node_nic(node_instance, attrs)
        nic = node_instance.interfaces.create(attrs)
        node_instance.interfaces.reload
        nic
      end

      def update_node_nic(node_instance, nic, attrs)
        nic.save(attrs)
        node_instance.interfaces.reload
      end

      def add_node_nics(node_instance)
      end

      def remove_node_nics(node_instance)
        Dopv::log.debug("Node #{nodename}: Removing (possible) network interfaces defined by template.")
        if block_given?
          node_instance.interfaces.each { |nic| yield(node_instance, nic) }
        else
          node_instance.interfaces.each(&:destroy) rescue nil
        end
        node_instance.interfaces.reload
      end

      def add_node_affinity(node_instance, affinity)
      end

      def remove_node_affinity(node_instance, affinity)
      end

      def add_node_volume(node_instance, config)
        node_instance.volumes.create(config)
      end

      def update_node_volume(node_instance, volume, attrs)
        node_instance.update_volume(attrs.merge(:id => volume.id))
        wait_for_task_completion(node_instance)
        node_instance.volumes.reload
        volume
      end

      def destroy_node_volume(node_instance, volume)
      end

      def attach_node_volume(node_instance, volume)
      end

      def detach_node_volume(node_instance, volume)
      end

      def add_node_data_volumes(node_instance)
        ::Dopv::log.info("Node #{nodename}: Adding data volumes.")

        ::Dopv::log.debug("Node #{nodename}: Loading data volumes DB.")
        data_volumes = data_disks_db.volumes

        # Check if persistent disks DB is consistent
        ::Dopv::log.debug("Node #{nodename}: Checking data volumes DB integrity.")
        data_volumes.each do |dv|
          # Disk exists in state DB but not in plan
          unless volumes_config.find { |cv| dv.name == cv.name }
            err_msg = "Inconsistent data volumes DB: Volume #{dv.name} exists in DB but not in plan"
            raise ProviderError, err_msg
          end
        end
        volumes_config.each do |cv|
          # Disk exists in a plan but it is not recorded in the state DB for a
          # given node
          if !data_volumes.empty? && !data_volumes.find { |dv| cv.name == dv.name }
            ::Dopv::log.warn("Node #{nodename}: Data volume #{cv.name} exists in plan but not in DB.")
          end
        end

        # Attach all persistent disks
        data_volumes.each do |dv|
          ::Dopv::log.debug("Node #{nodename}: Attaching data volume #{dv.name} [#{dv.id}].")
          begin
            attach_node_volume(node_instance, dv)
          rescue Exception => e
            err_msg = "An error occured while attaching data volume #{dv.name}: #{e}"
            raise ProviderError, err_msg
          end
        end

        # Create those disks that do not exist in peristent disks DB and
        # record them into DB
        volumes_config.each do |cv|
          unless data_disks_db.volumes.find { |v| v.name == cv.name }
            ::Dopv::log.debug("Node #{nodename}: Creating disk #{cv.name} [#{cv.size.g} G].")
            volume = add_node_volume(node_instance, cv)
            record_node_data_volume(volume) unless volume.nil?
          end
        end
      end

      def record_node_data_volume(volume)
        ::Dopv::log.debug("Node #{nodename}: Recording data volume #{volume[:name]} into data volumes DB.")
        data_disks_db << volume.merge(:node => nodename)
      end

      def erase_node_data_volume(volume)
        ::Dopv::log.debug("Node #{nodename}: Erasing data volume #{volume.name} from data volumes DB.")
        data_disks_db.delete(volume)
      end

      def add_node_affinity(node_instance, name)
      end

      def add_node_affinities(node_instance)
        infrastructure_properties.affinity_groups.each { |a| add_node_affinity(node_instance, a) }
      end

      def execute_hook(hook_name, state_changed = false)
        has_changes = state_changed ? 1 : 0
        hooks.send(hook_name).each do |prog|
          prog_name = File.basename(prog)
          ::Dopv::log.info("Node #{nodename}: Executing #{hook_name}[#{prog_name}].")
          o, e, s = Open3.capture3(sanitize_env, "#{prog} #{nodename} #{has_changes}", :unsetenv_others => true)
          ::Dopv::log.debug("Node #{nodename}: #{hook_name}[#{prog_name}] standard output:\n#{o.chomp}")
          ::Dopv::log.warn("Node #{nodename}: #{hook_name}[#{prog_name}] non-zero exit status #{s.exitstatus}") unless s.success?
          ::Dopv::log.debug("Node #{nodename}: #{hook_name}[#{prog_name}] standard error:\n#{e.chomp}") unless e.chomp.empty?
        end
      end

      def record_node_instance(node_instance)
        nodename
        node_ips
      end

      def node_ips(node_instance)
        []
      end
    end
  end
end
