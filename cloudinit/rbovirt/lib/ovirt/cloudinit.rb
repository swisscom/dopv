module OVIRT

  class Cloudinit < BaseObject
    attr_reader :vm
    attr_reader :hostname

    def initialize(client=nil, xml={})
      binding.pry
      if xml.is_a?(Hash)
        super(client, xml[:id], nil, nil)
        @hostname = xml[:hostname]
      else
        super(client, xml[:id], nil, nil)
        parse_xml_attributes!(xml)
      end
      self
    end

    def self.to_xml(opts={})
      builder = Nokogiri::XML::Builder.new do
        vm {
          initialization {
            cloud_init {
              # Host name cloud init entry
              host {
                address(opts[:hostname])
              } if opts[:hostname]
              
              # Timezone cloud init entry
              timezone(opts[:timezone]) if opts[:timezone]
              
              # User login name/password entries
              users {
                opts[:users].each do |user|
                  user_ {
                    user_name(user[:user_name]) if user[:user_name]
                    password(user[:password]) if user[:password]
                  } if user.is_a?(Hash)
                end
              } if opts[:users] .is_a?(Array)
              
              # User ssh public key entries
              authorized_keys {
                opts[:authorized_keys].each do |authorized_key|
                  authorized_key_ {
                    user { user_name(authorized_key[:user_name]) }
                    key(authorized_key[:key])
                  } if authorized_key.is_a?(Hash) and authorized_key[:user_name] and authorized_key[:key]
                end
              } if opts[:authorized_keys].is_a?(Array)

              # SSH server regeneration
              regenerate_ssh_keys(opts[:regenerate_ssh_keys] == true ? 'true' : 'false')
              
              # Networking configuration
              network_configuration {
                boot_protocol = 'NONE'
                # Network interfaces setup
                nics {
                  opts[:nics].each do |nic|
                    nic_ {
                      name_(nic[:name])
                      if nic[:boot_protocol].is_a?(String)
                        case nic[:boot_protocol].upcase
                        when 'STATIC'
                          boot_protocol = 'STATIC'
                        when 'DHCP'
                          boot_protocol = 'DHCP'
                        end
                      end
                      boot_protocol_(boot_protocol)
                      on_boot = nic[:on_boot] == true ? 'true' : 'false'
                      on_boot_(on_boot)
                      network {
                        nic_attrs = {}
                        nic_attrs[:address] = nic[:address] if nic[:address].is_a?(String) and not nic[:address].empty?
                        nic_attrs[:netmask] = nic[:netmask] if nic[:netmask].is_a?(String) and not nic[:netmask].empty?
                        nic_attrs[:gateway] = nic[:gateway] if nic[:gateway].is_a?(String) and not nic[:gateway].empty?
                        ip(nic_attrs) if boot_protocol == 'STATIC' and not nic_attrs.empty?
                      } if nic.is_a?(Hash) and nic[:name].is_a?(String) and not nic[:name].empty?
                    }
                  end
                } if opts[:nics].is_a?(Array)
                # DNS setup
                dns {
                  opts[:dns].each do |key, val|
                    if key == :servers || key == :search_domains
                      send(key) {
                        if val.is_a?(Array)
                          val.each do |ent|
                            host {
                              address(ent)
                            }
                          end
                        end
                      }
                    end
                  end
                } if opts[:dns].is_a?(Hash) and boot_protocol == 'STATIC'
              } if opts[:nics].is_a?(Array) or opts[:dns].is_a?(Hash)
            }
          }
        }
      end
      #binding.pry
      Nokogiri::XML(builder.to_xml).root.to_s
    end

    def parse_xml_attributes!(xml)
      @hostname = (xml/'initialization/cloud_init') rescue nil
      @vm = Link::new(@client, (xml/'vm').first[:id], (xml/'vm').first[:href]) if (xml/'vm') rescue nil
    end

  end
end

# vim:ts=2:sw=2:expandtab
