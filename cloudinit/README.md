# Cloudinit

An implementation of cloud init into rbovirt and fog library.

## Installation

This code should be merged into upstream. At the moment, mainly due to quicker
development, it is kept as a part of `dopv`.

### Prerequisities

1. `rbovirt` of version 0.0.29
2. `fog` of version 1.25.0

### Installation of rbovirt

	$ cp rbovirt/lib/client/vm_api.rb ${HOME}/.gem/ruby/gems/rbovirt-0.0.29/lib/client/vm_api.rb
	$ cp rbovirt/lib/ovirt/cloudinit.rb ${HOME}/.gem/ruby/gems/rbovirt-0.0.29/lib/ovirt/cloudinit.rb
	$ cp rbovirt/lib/rbovirt.rb ${HOME}/.gem/ruby/gems/rbovirt-0.0.29/lib/rbovirt.rb

