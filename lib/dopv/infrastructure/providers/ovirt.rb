require 'fog'
require 'uri'
require 'open-uri'

module Dopv
  module Infrastructure
    module Ovirt
      # Based on http://docs.openstack.org/openstack-ops/content/flavors.html
      FLAVOR = {
        :tiny     => {
          :cores    => 1,
          :memory   => 536870912,
          :storage  => 1073741824
        },
        :small    => {
          :cores    => 1,
          :memory   => 2147483648,
          :storage  => 10737418240
        },
        :medium   => {
          :cores    => 2,
          :memory   => 4294967296,
          :storage  => 10737418240
        },
        :large    => {
          :cores    => 4,
          :memory   => 8589934592,
          :storage  => 10737418240
        },
        :xlarge   => {
          :cores    => 8,
          :memory   => 1744830464,
          :storage  => 10737418240
        }
      }

      class Node < BaseNode
        def initialize(node_config)
          @compute_client = nil
          vm = nil

          cloud_init = { :hostname => node_config[:nodename] }
          if node_config[:interfaces][0][:ip_address] != 'dhcp'
            cloud_init[:nicname]  = node_config[:interfaces][0][:name]
            cloud_init[:ip]       = node_config[:interfaces][0][:ip_address]
            cloud_init[:netmask]  = node_config[:interfaces][0][:ip_netmask]
            cloud_init[:gateway]  = node_config[:interfaces][0][:ip_gateway]
          end
          
          begin
            # Try to get the datacenter ID first.
            @compute_client = create_compute_client(
              :username     => node_config[:provider_username],
              :password     => node_config[:provider_password],
              :endpoint     => node_config[:provider_endpoint],
              :datacenter   => node_config[:datacenter]
            )

            # Create a VM
            vm = @compute_client.servers.create(
              :name     => node_config[:nodename],
              :template => get_template_id(node_config[:image]),
              :cores    => FLAVOR[node_config[:flavor].to_sym][:cores],
              :memory   => FLAVOR[node_config[:flavor].to_sym][:memory],
              :storage  => FLAVOR[node_config[:flavor].to_sym][:storage],
              :cluster  => get_cluster_id(node_config[:cluster])
            )

            # Wait until all locks are released
            vm.wait_for { !locked? }
            
            # Remove all interfaces defined by the template
            vm.interfaces.each { |interface| vm.destroy_interface(:id => interface.id) }
            # Create all interfaces defined in node configuration
            node_config[:interfaces].each do |interface|
              begin
                network = @compute_client.list_networks(vm.cluster).find { |n| n.name == interface[:network] }
              rescue
                raise Errors::ProviderError, "Cannot create interface, no such network '#{interface[:network]}'"
              end
                vm.add_interface(
                  :network  => network.id,
                  :name     => interface[:name],
                  :plugged  => true,
                  :linked   => true,
                )
                vm = vm.save
            end
            
            # Start a node with cloudinit
            vm.service.vm_start_with_cloudinit(:id => vm.id, :user_data => cloud_init)

            # Reload the node
            vm.reload
          rescue Exception => e 
            vm.destroy if vm
            raise Errors::ProviderError, "Error while creating '#{node_config[:nodename]}': #{e}"
          end
        end

        private

        def get_endpoint_ca_cert(url)
          uri = URI.parse(url)
          local_ca_file  = "/tmp/#{uri.hostname}_#{uri.port}_ca.crt"
          remote_ca_file = "#{uri.scheme}://#{uri.host}:#{uri.port}/ca.crt"
          local_ca = remote_ca = nil
          unless File.exists?(local_ca_file)
            begin
              remote_ca = open(remote_ca_file, :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE)
              local_ca  = open(local_ca_file, 'w')
              local_ca.write(remote_ca.read)
            rescue
              raise Errors::ProviderError, "Cannot download CA certificate from #{uri.host}"
            ensure
              remote_ca.close if remote_ca
              local_ca.close if local_ca
            end
          end
          local_ca_file
        end

        def create_compute_client(attrs)
          # Find the datacenter ID
          compute_client = Fog::Compute.new(
              :provider           => 'ovirt',
              :ovirt_username     => attrs[:username],
              :ovirt_password     => attrs[:password],
              :ovirt_url          => attrs[:endpoint],
              :ovirt_ca_cert_file => get_endpoint_ca_cert(attrs[:endpoint]),
              :ovirt_ca_no_verify => true
          )
          begin
            datacenter_id = compute_client.datacenters.find { |dc| dc[:name] == attrs[:datacenter] }[:id]
          rescue
            raise Errors::ProviderError, "No such datacenter '#{attrs[:datacenter]}'"
          end
          # Get a new compute client from a proper datacenter
          Fog::Compute.new(
              :provider           => 'ovirt',
              :ovirt_username     => attrs[:username],
              :ovirt_password     => attrs[:password],
              :ovirt_url          => attrs[:endpoint],
              :ovirt_ca_cert_file => get_endpoint_ca_cert(attrs[:endpoint]),
              :ovirt_ca_no_verify => true,
              :ovirt_datacenter   => datacenter_id
          )
        end

        def get_cluster_id(cluster_name)
          begin
            @compute_client.list_clusters.find { |cl| cl[:name] == cluster_name }[:id]
          rescue
            raise Errors::ProviderError, "No such cluster '#{cluster_name}'"
          end
        end

        def get_template_id(template_name)
          begin
            @compute_client.list_templates.find { |tpl| tpl[:name] == template_name }[:id]
          rescue
            raise Errors::ProviderError, "No such template '#{template_name}'"
          end
        end
      end
    end
  end
end
