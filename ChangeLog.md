# 0.2.2 20.10.2015
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
