# 0.13.0 24.04.2017
## [deps]
   * Update `dop_common`

## [vsphere]
 * Some minor fixes and improvements
   * Fix typo customization_domain_password in `customize_node_instance`
   * Addition filtering apipa and ipv6 in `get_node_ip_addresses`
   * Add ability to transform disks during clone from template (see plan node property thin_clone)
   * Add missing requires
   * Cleanup unnecessary delegators

# 0.12.0 07.04.2017
## [vsphere]
 * Improve `destroy_node`
   * Waiting for poweredOff vm state
 * Improve `get_node_ip_addresses`
   * Filtering apipa and ipv6
   * Skipping if vm tools unmanaged or has no connected guest network interface
 * Improve `customize_node_instance` windows sysprep
   * Add ability to join domain or workgroup
 * Some minor fixes and improvements
   * `@wait_params` to instance
   * Handling of properties thin/thick provisioning, timezone and product_id

# 0.11.0 29.03.2017
## [general]
 * Split log files by nodes
 * Prevent crash when a plan was deployed with an older version

## [cli]
 * Logfile options are now the same as in dopi
 * The output format is now smaller by default. The old behaviour where the log entry contained
   the code line of the message can be activated with the "--trace" flag. 

# 0.10.1 08.03.2017

## [cli]
 * Add a resfresh command to update node information in the local state store
 * Make sure the plan exists for deploy/undeploy/refresh commands

## [general]
 * Make sure the ip list in the state store is clean

# 0.10.0 22.02.2017

## [base]
 * Implement `erase_node_instance`

## [vsphere]
 * Implement `get_node_ip_addresses`

# 0.9.0 15.02.2017
## [base]
 * Implement node state recording

## [openstack]
 * Implement `get_node_ip_addresses`

## [plan]
 * Plan updates for l13ch and lab1ch

# 0.8.1 14.02.2017

## [vsphere]
 * Remove obsolete `searchdomains` method
 * Move vsphere-related delegators into `VSPhere` class

# 0.8.0 02.02.2017

## [plan]
 * Use the preprocessor in the validation method

## [cli]
 * Removed deprecated options

## [general]
 * Parallelization impelentation
 * Implement common configuration

## [deps]
 * Update of `dop_common`

# 0.7.3 21.12.2016

## [log]
 * Do not write color escape sequences into log files.

## [cli]
 * Deprecate required options in favor of arguments in order to make dopv cli
   consistent with dopi's one

## [plan]
 * Make sure the plan update is automatically ignored for now and update on add
   as well

## [general]
 * Implement console rake target

## [spec]
 * Implement basic rspec framework
 * Implement basic tests of:
   * `Dopv`
   * `Dopv::VERSION`
   * `Dopv::Plan`
   * `Dopv::PersistentDisk::Entry`

# 0.7.2 07.12.2016
 * Update `dop_common` and update required parts of `dopv` code

# 0.7.1 06.12.2016
 * Update `dop_common`

# 0.7.0 06.12.2016

## [doc]
 * Update documentation

## [general]
 * Basic node filtering implemented

# 0.6.0 05.12.2016

## [deps]
 * Update `dop_common`

## [base]
 * Implement hooks

# 0.5.1 29.11.2016

## [deps]
 * Update `dop_common`

# 0.5.0 21.11.2016

## [plan]
 * Plan store implemented

## [cli]
 * CLI redesign

## [general]
 * Minor fixes


# 0.4.1 15.11.2016
 * Revert `#895e4cdbf65`
 * Reimplement logging
 * Update to `dop_common` 0.9.1

## [disk db]
 * Update the disk DB to use `dop_common` plan store while keeping the
   possibility to dump the file.

# 0.4.0 14.11.2016

## [plan]
  * Replaced with DopCommon parser v0.9.0

## [ovirt]
  * Use common parser

## [openstack]
  * Use common parser

## [vsphere]
  * Use common parser

# 0.3.9 06.11.2016

## [openstack]
 * Fix security groups removal
 * Make sure floating IPs and network ports are removed before the node is
   destroyed, otherwise the process leaves orphan network ports during
   udeployment

# 0.3.8 02.11.2016

## [plan]
 * Improve parser
 * Implement `domain_id` and `endpoint_type` infrastructure properties that
   are required for openstack providers. The `domain_id` defaults to
   `default` and the `endpoint_type` defaults to `publicURL`.

## [openstack]
 * Implement `provider_domain_id` and `provider_endpoint_type`

# 0.3.7 01.11.2016

## [dependencies]
 * Update to fog-1.36.0

## [openstack]
  * Use `openstack_project_name` instead of `openstack_tenant`.
  * Use `openstack_domain_id`; `default` is used if it isn't specified.
  * Remove `volume_provider` and use compute's volumes instead as it saves some
	API calls.

# 0.3.6 17.10.2016

## [dependencies]
 * Use fog_profitbricks version that is compatible with ruby 1.9.x

# 0.3.5 21.09.2016

## [plan]
 * Fix that not all infrastructure_properties are required by providers

# 0.3.4 01.09.2016

## [plan]
 * Better error messages for infrastructure_properties validation.
 * Implement support for security groups.

## [openstack]
 * Implement support for security groups.

# 0.3.3 24.08.2016

## [samples]
 * Include plan and disk DB for lab10ch.

## [ovirt]
 * Update rbovrit to fix cloudinit issues with multiple nameserver entries.

# 0.3.2 04.08.2016

## [general]
 * Better support for pry integration.
 * Support for ruby193 and ruby22x.

# 0.3.1 03.08.2016

## [ovirt]
 * Automatically choose the first network, rather than a hardcoded one.

# 0.3.0 20.06.2016

## [general]
 * Drop support for ruby 1.9.3 in favor of 2.2+

# 0.2.8 14.06.2016

## [plan]
 * Make sure that `use_config_drive` is set to `true` if not present in node's
   definition.

# 0.2.7 08.06.2016

## [plan]
 * Allow networks without a default gateway. Must set `ip_defgw` to `false` AND
   `set_defaultgw` to `false` on a host level.

# 0.2.6 06.05.2016

## [ovirt]
 * `stop_node_instance` - wait until the node is down

## [dependencies]
 * Updated to use rbovirt-0.1.1

## [plan]
 * Implement `use_config_drive` infrastructure property. By default it is set to
   `true`, i.e. to use config drive.

## [openstack]
 * Implement `config_drive?` method for switching the config drive on and off

# 0.2.5 11.01.2016

## plan
 * implement deprecation warning if no `ip` is defined for a network interface.
   Please note that valid IP definitions are:
   * valid IP string
   * dhcp string
   * none string

# 0.2.4 07.12.2015

## plan
 * make sure `{}` is accepted as a valid network entry
 * implement newer definition of credentials
 * support `nil` network definitions for backward compatibility

# 0.2.3 06.11.2015

## [ovirt]
 * implement default storage domain for root and data disks. This can be used to
   specify which storage domain should be used for disks defined by the template
   during provisioning of VM.
 * Bundle rbovrit with cloud-init fix for RHEV 3.5.5 and above.

# 0.2.2 20.10.2015
## [cli]
 * improve error handling

## [plan]
 *  make stricter validation of node's interfaces

## [ovirt]
 * implement management of additional NICs via cloud-init


# 0.2.1 18.08.2015
## [core]
 * Remove `lib/infrastructure/core.rb`. Move things into `lib/infrastructure.rb`

## [doc]
 * Update documentation

## [general]
 * Implement _undeploy_ action that removes a deployment according to a plan and
   optionally removes also data volumes on a target cloud provider as well as
   from persistent volumes database

## [persistent_disk]
 * Refactor of `PersistenDisk#update` and `PersistentDisk#delete` methods

## [infrastructure]
 * Refactor dynamic provider loader
 * Simplify provider supported types and provider to class name lookups
 * Fix broken memory definition of xlarge flavor

## [base]
 * `add_node_nic` returns freshly created nic object

## [ovirt]
 * `add_node_nic` returns freshly created nic object

## [openstack]
 * Wait until the node is down in `Infrastructure::OpenStack#stop_node_instance`
 * Implement `manage_etc_hosts` in `Infrastructure::OpenStack#cloud_config`

# 0.2.0 23.07.2015

## [core]
 * Implement GLI parser for dopv command line tool
   * Implement `exit_code` method to PlanError and ProviderError
   * Fix parsing of `caller` in `Dopv::log_init` method
 * Update to fog-1.31.0
 * Update rhosapi-lab15ch deployment plan


# 0.1.1 22.07.2015
## [openstack]
 * Floating IP implementation

# 0.1.0 14.07.2015

## [general]
New major release with rewritten infrastructure code base and bare metal and
openstack cloud providers

Following has been refactored:
 * Infrastructure refactoring
   * Unified method names and variables
   * Ready to use destroy_* methods hence implementation of destroying of
     deployment can be done easily
   * Fixes in data disks manipulation routines

 * Plan refactoring
   * More information has been added to error messages in infrastructure and
     network validation part

 * General refactoring
   * Error messages moved to appropriate modules

## [plan]
 * Simplify plan parser
   * remove superfluos conditional statements in assignments of node properties
   * do not evaluate networks definition for bare metal

## [base]
 * Add `set_gateway?` method
 * Fix detachment of disks in destroy method

## [openstack]
 * Flavor method returns m1.medium as a flavor, hence the flavor keyword may be
   optional
 * change instance to node_instance in `wait_for_task_completion` method to keep
   parameters consistent accross codebase
 * Add openstack node customization
 * Fix appending nil class to string
 * Add support for customization
 * Implement networking support. No floating IPs yet
 * Fix syntax error in `add_network_port`
 * Add initial network handling
 * Initial implementation of openstack provider

## [vsphere]
 * Reword `apikey` keyword to `provider_pubkey_hash`
 * Add automatic public key hash retrieval so that `provider_pubkey_hash` is
   optional


# 0.0.20 29.06.2015

## [vsphere]
 * Fix NIC creation in VCenters with multiple DCs -> `:datacenter =>
   vm.datacenter` is passed during NIC creation
   [CLOUDDOPE-891](https://issue.swisscom.ch/browse/CLOUDDOPE-891)

# 0.0.20 23.06.2015

## [parser]
 * Improved network definition checks in infrastructures. They are checked as
   in case they are defined thus baremetal may have network definitions as well
   for future

# 0.0.19 23.06.2015

## [parser]
 * Make infrastructure credentials optional (defaults to `nil`)
 * Make infrastructure endpoint optional (defaults to `nil`)
 * Do not check for network definitions when the provider is *baremetal*

## [baremetal]
 * Fix wrong number of parameters error

# 0.0.18 18.06.2015

## [ovirt]
 * Support provisioning mechanism, i.e. tnin and/or thick provisioning of data
   disks [CLOUDDOPE-873](https://issue.swisscom.ch/browse/CLOUDDOPE-873)

# 0.0.17 17.06.2015

## [baremetal]
 * Fix missing provider file for  metal infrastructures
   [CLOUDDOPE-828](https://issue.swisscom.ch/browse/CLOUDDOPE-828)

# 0.0.16 05.06.2015

## [parser]
 * Make `interfaces` and `image` of a node configuration hash optional

## [baremetal]
 * New provider for bare metal infrastructures
   [CLOUDDOPE-828](https://issue.swisscom.ch/browse/CLOUDDOPE-828)

# 0.0.15 08.05.2015

## [vsphere]
 * Fix removal of empty interface list in add_interfaces
   [CLOUDDOPE-732](https://issue.swisscom.ch/browse/CLOUDDOPE-732)

# 0.0.14 05.05.2015

## [general]
 * Fixed `can't convert nil into String` when no disk db file is given
   [CLOUDDOPE-723](https://issue.swisscom.ch/browse/CLOUDDOPE-723)

# 0.0.13 01.05.2015

## [general]
 * Updated fog to 1.29.0
 * Updated rbovirt to upstream@f4ff2b8daf89
 * Removed obsolete deployment plans
 * Added new example deployment plans

## [parser]
 * Added support for `virtual_switch`
 * Updated error messages in `plan.rb`
 * Fixed handling of `ip` record of a node

## [vsphere]
 * Added support for DVS -> the DV switch is defined by `virtual_switch`
   property

# 0.0.12 28.04.2015

## [parser]
 * Added support for `dest_folder`

## [rbovirt]
 * None

## [vsphere]
 * Added support for `dest_folder`
 * Added support for `default_pool`
