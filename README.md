# Dopv

Dopv orchestrates deployments of nodes. A node can be a virtual machine or a bare-metal compute node. 

## Installation

Add this line to your application's Gemfile:

    gem 'dopv'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install dopv

## Usage

### Library
Deploy a plan
```ruby
require 'dopv'
plan = ::Dopv::load_plan(plan_file)
data_volumes_db = ::Dopv::load_data_volumes_db(db_file)
::Dopv::run_plan(plan, data_volumes_db)
```
Undeploy a plan while keeping data volumes
```ruby
require 'dopv'
plan = ::Dopv::load_plan(plan_file)
data_volumes_db = ::Dopv::load_data_volumes_db(db_file)
::Dopv::run_plan(plan, data_volumes_db, :undeploy)
```
Undeploy a plan and remove data volumes from infrastructure provider (stack) as
well as from persistent data volumes DB:
```ruby
require 'dopv'
plan = ::Dopv::load_plan(plan_file)
data_volumes_db = ::Dopv::load_data_volumes_db(db_file)
::Dopv::run_plan(plan, data_volumes_db, :undeploy, true)
```

### CLI
A command line interface utility `dopv` is provided.

#### Getting help
A help can be obtained by calling `dopv -h`:
```
dopv --help
NAME
    dopv - DOPv command line tool

SYNOPSIS
    dopv [global options] command [command options] [arguments...]

VERSION
    0.2.0

GLOBAL OPTIONS
    --help                         - Show this message
    --logfile, -l path_to_log_file - Log file (default: STDOUT)
    --[no-]trace, -t               - Show stacktrace on crash
    --verbosity, -v level          - Verbosity of the command line tool (default: info)
    --version                      - Display the program version

COMMANDS
    deploy   - Deploy a plan
    help     - Shows a list of commands or help for one command
    undeploy - Undeploy a plan
```

#### Deploying a plan
To get a help on deploy CLI options launch `dopv` `help deploy` argument:
```
$ dopv help deploy
NAME
    deploy - Deploy a plan

SYNOPSIS
    dopv [global options] deploy [command options]

COMMAND OPTIONS
    --diskdb, -d path_to_db_file - (default: none)
    --plan, -p path_to_plan_file - (required, default: none)
```

To deploy a plan located at `/tmp/plan.yaml` and store and/or load persistent disks database located at `/tmp/pdisks.yaml` one can launch `dopv` with following options:
```
$ dopv deploy -p  /tmp/pdisks.yaml -d /tmp/pdisks.yaml
```

Please note that disk database file is created if it does not exist.

#### Undeploying a plan
To get a help on undeploy CLI options launch `dopv` `help undeploy` argument:
```
$ dopv help undeploy
NAME
    undeploy - Undeploy a plan

SYNOPSIS
    dopv [global options] undeploy [command options]

COMMAND OPTIONS
    --diskdb, -d path_to_db_file - (default: none)
    --plan, -p path_to_plan_file - (required, default: none)
    --[no-]rmdisk, -r            -

```

In order to destroy a deployment specified by a plan located at `/tmp/plan.yaml` and persistent disks database located at `/tmp/pdisks.yaml` one can launch `dopv` with following options:
```
$ dopv undeploy -p  /tmp/pdisks.yaml -d /tmp/pdisks.yaml
```
If you also want to remove the data volumes of each node and remove their records from persistent data volumes DB, please specify `-r` or `--rmdisk` option as shown bellow:
```
$ dopv undeploy -p  /tmp/pdisks.yaml -d /tmp/pdisks.yaml
```

#### Logging
By default `dopv` logs messages with `INFO` level and higher to standard output. In order to log to a file `-l` can be specified. The `-v` option is used to set a different log threshold. Following is an example of logging everything (`DEBUG` and above) into `/tmp/dopv.log` during plan deployment:
```
$ dopv -l /tmp/dopv.log -v debug deploy -p /tmp/plan.yaml -d /tmp/disks.yaml
```

## Plan
A plan format and description can be found [here](https://gitlab.swisscloud.io/clu-dop/dop_common/blob/master/doc/plan_format_v0.0.1.md). A plan example can be found [here](https://gitlab.swisscloud.io/clu-dop/dop_common/blob/master/doc/examples/example_deploment_plan_v0.0.1.yaml)


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
