require 'fog'
require 'uri'
require 'open-uri'

module Dopv
  module Cloud
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
        def initialize(config)
          @config = config
          cloud_init = { :hostname => @config[:nodename] }
          if @config[:nets][0][:proto] == 'static'
            cloud_init[:nicname] = @config[:nets][0][:int]
            cloud_init[:ip] = @config[:nets][0][:ip]
            cloud_init[:netmask] = @config[:nets][0][:netmask]
            cloud_init[:gateway] = @config[:nets][0][:gateway]
          end
          begin
            # Create new compute client instance.
            @compute_client = Fog::Compute.new(
              :provider           => @config[:provider],
              :ovirt_username     => @config[:provider_username],
              :ovirt_password     => @config[:provider_password],
              :ovirt_url          => @config[:provider_endpoint],
              :ovirt_ca_cert_file => get_ovirt_ca_cert
            )
            # Create new virtual machine instance.
            vm = @compute_client.servers.create(
              :name     => @config[:nodename],
              :template => get_template_id,
              :cores    => FLAVOR[@config[:flavor].to_sym][:cores],
              :memory   => FLAVOR[@config[:flavor].to_sym][:memory],
              :storage  => FLAVOR[@config[:flavor].to_sym][:storage]
            )
            # Wait until all locks are released and start the node with cloud
            # init.
            vm.wait_for { !locked? }
            vm.service.vm_start_with_cloudinit(:id => vm.id, :user_data => cloud_init)
            vm.reload
          rescue Exception => e 
            raise Errors::ProviderError, "Error while creating '#{@config[:nodename]}': #{e}"
          end
        end

        private

        def get_ovirt_ca_cert
          uri = URI.parse(@config[:provider_endpoint])
          local_ca_file  = "/tmp/#{uri.hostname}_#{uri.port}_ca.crt"
          remote_ca_file = "#{uri.scheme}://#{uri.host}:#{uri.port}/ca.crt"
          local_ca = remote_ca = nil
          unless File.exists?(local_ca_file)
            begin
              remote_ca = open(remote_ca_file, 'r')
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

        def get_template_id
          id = nil
          @compute_client.list_templates.each { |t| id = t[:raw].id if t[:raw].name == @config[:image] }
          raise Errors::ProviderError, "No such template #{@config[:image]}" unless id
          id
        end
      end
    end
  end
end
