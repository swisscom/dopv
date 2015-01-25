require 'dopv/base_node'
require 'uri'
require 'fog'

module Dopv
  module Cloud
    module Ovirt
      class Node < Dopv::BaseNode
        def initialize(config)
          @config = config
          cloud_init = { :hostname => @config[:nodename] }
          if @config[:nets][0][:proto] == 'static'
            cloud_init[:nicname] = @config[:nets][0][:int]
            cloud_init[:ip] = @config[:nets][0][:ip]
            cloud_init[:netmask] = @config[:nets][0][:netmask]
            cloud_init[:gateway] = @config[:nets][0][:gateway]
          end

          case config[:flavor]
          when 'small'
            cpu, ram = 1, 1
          when 'medium'
            cpu, ram = 2, 2
          when 'large'
            cpu, ram = 2, 4
          else
            cpu, ram = 1, 1
          end

          @compute_client = Fog::Compute.new(
            :provider => @config[:provider],
            :ovirt_username => @config[:provider_username],
            :ovirt_password => @config[:provider_password],
            :ovirt_url => @config[:provider_endpoint],
            :ovirt_ca_cert_file => get_ovirt_ca_cert
          )
          vm = @compute_client.servers.create(
            :name => @config[:nodename],
            :template => get_template_id
          )
          vm.wait_for { !locked? }
          vm.service.vm_start_with_cloudinit(:id => vm.id, :user_data => cloud_init)
          vm.reload
        end

        private

        def get_ovirt_ca_cert
          uri = URI.parse(@config[:provider_endpoint])
          local_ca_file = "/tmp/#{uri.hostname}_#{uri.port}_ca.crt"
          remote_ca_file = "#{uri.scheme}://#{uri.host}:#{uri.port}/ca.crt"
          unless File.exists?(local_ca_file)
            require 'open-uri'
            begin
              open(remote_ca_file) do |r|
                puts r
                f = File.open(local_ca_file, 'w')
                f.write(r.read)
                f.close
              end
            rescue
              raise Dopv::Errors::ProviderError, "Cannot download CA certificate from #{uri.host}"
            end
          end
          local_ca_file
        end

        def get_template_id
          id = nil
          @compute_client.list_templates.each { |t| id = t[:raw].id if t[:raw].name == @config[:image] }
          id
        end

      end
    end
  end
end
