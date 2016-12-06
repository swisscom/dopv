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
A help can be obtained by calling `dopv --help`:
```
$ dopv --help
NAME
    dopv - DOPv command line tool

SYNOPSIS
    dopv [global options] command [command options] [arguments...]

VERSION
    0.7.0

GLOBAL OPTIONS
    --help                         - Show this message
    --logfile, -l path_to_log_file - Log file (default: none)
    --[no-]trace, -t               - Show stacktrace on crash
    --verbosity, -v level          - Verbosity of the command line tool (default: info)
    --version                      - Display the program version

COMMANDS
    add      - Add a new plan file to the plan cache
    deploy   - Deploy a plan
    export   - Export the internal disk state into a local diskdb file
    help     - Shows a list of commands or help for one command
    import   - Import a diskdb file into the internal state store
    list     - Show the list of plans in the plan store
    remove   - Remove an existing plan from the plan cache
    undeploy - Undeploy a plan
    update   - Update the plan and/or the plan state for a given plan yaml or plan name.
    validate - Validate plan file
```

#### Validating a plan
The deployment plan `/tmp/foo_plan.yml` could be validated by issuing:
```
$ dopv validate -p /tmp/foo_plan.yml
Plan valid.
```

Please note that the plan is always validated before any action takes place.

#### Adding a plan
In order to add a plan to plan cache, use `dopv` `add` command:
```
$ dopv add /tmp/bar_plan.yml
```

Please note that this feature is considered experimental and should be used with extreme care.

#### Updating a plan
In order to update a plan in the cache after some local changes have been introduced, use `dopv`
`update` command:
```
$ dopv update /tmp/bar_plan.yml
```

One may use `-c` or `-i` in order to remove the existing disk information and start with a clean
state or to ignore the update and to merely set it to the latest version.

Please note that this feature is considered experimental and should be used with extreme care.

#### Listing plans in cache
One may use the `list` command to check which plans are stored in the plan cache.

#### Deploying a plan
To get a help on deploy CLI options launch `dopv help deploy` argument:
```
$ dopv help deploy
NAME
    deploy - Deploy a plan

SYNOPSIS
    dopv [global options] deploy [command options]

COMMAND OPTIONS
    --diskdb, -d path_to_db_file                                             - Use a local diskdb file and import/export it automatically (default: none)
    --exclude_nodes=node01.example.com,node02.example.com,/example\.com$/    - Exclude this nodes from the run (default: )
    --exclude_nodes_by_config='{"var1": ["val1", "/val2/"], "var2": "val2"}' - Exclude nodes with this config from the run (You have to specify a JSON hash here) (default: {})
    --exclude_roles=role01,role01,/^rolepattern/                             - Exclude this roles from the run (default: )
    --nodes=node01.example.com,node02.example.com,/example\.com$/            - Run plans for this nodes only (default: )
    --nodes_by_config='{"var1": ["val1", "/val2/"], "var2": "val2"}'         - Run plans for this nodes with this config only (You have to specify a JSON hash here) (default: {})
    --plan, -p path_to_plan_file                                             - plan name from the store or plan file to deploy. If a plan file is given DOPv will run in oneshot mode and add/remove
                                                                               the plan automatically to the plan store (required, default: none)
    --roles=role01,role01,/^rolepattern/                                     - Run plans for this roles only (default: )
```
To deploy a plan located at `/tmp/plan.yaml` and store and/or load persistent disks database located at `/tmp/pdisks.yaml` one can launch `dopv` with following options:
```
$ dopv deploy -p  /tmp/pdisks.yaml -d /tmp/pdisks.yaml
```

To deploy only nodes matching a regular expression `^foo-[1-9]+\.bar\.baz$` that are defined in a plan called `/tmp/plan.yaml` and store and/or load persistent disks database located at `/tmp/pdisks.yaml` one can launch `dopv` with following options:
```
$ dopv deploy -p  /tmp/pdisks.yaml -d /tmp/pdisks.yaml --nodes=/^foo-[1-9]+\.bar\.baz$/
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
 ME
    undeploy - Undeploy a plan

SYNOPSIS
    dopv [global options] undeploy [command options]

COMMAND OPTIONS
    --diskdb, -d path_to_db_file                                             - Use a local diskdb file and import/export it automatically (default: none)
    --exclude_nodes=node01.example.com,node02.example.com,/example\.com$/    - Exclude this nodes from the run (default: )
    --exclude_nodes_by_config='{"var1": ["val1", "/val2/"], "var2": "val2"}' - Exclude nodes with this config from the run (You have to specify a JSON hash here) (default: {})
    --exclude_roles=role01,role01,/^rolepattern/                             - Exclude this roles from the run (default: )
    --nodes=node01.example.com,node02.example.com,/example\.com$/            - Run plans for this nodes only (default: )
    --nodes_by_config='{"var1": ["val1", "/val2/"], "var2": "val2"}'         - Run plans for this nodes with this config only (You have to specify a JSON hash here) (default: {})
    --plan, -p path_to_plan_file                                             - plan name from the store or plan file to undeploy. If a plan file is given DOPv will run in oneshot mode and
                                                                               add/remove the plan automatically to the plan store (required, default: none)
    --[no-]rmdisk, -r                                                        - Remove the disks
    --roles=role01,role01,/^rolepattern/                                     - Run plans for this roles only (default: )   --[no-]rmdisk, -r            -
```

In order to destroy a deployment specified by a plan located at `/tmp/plan.yaml` and persistent disks database located at `/tmp/pdisks.yaml` one can launch `dopv` with following options:
```
$ dopv undeploy -p  /tmp/pdisks.yaml -d /tmp/pdisks.yaml
```
If you also want to remove the data volumes of each node and remove their records from persistent data volumes DB, please specify `-r` or `--rmdisk` option as shown bellow:
```
$ dopv undeploy -p  /tmp/pdisks.yaml -d /tmp/pdisks.yaml -r
```
If you'd like to selectively remove a node called `foo.bar.baz` as well as nodes that match regular expression `^foo[1-5]\.bar\.baz$` and their data disks, you would use `--nodes` filter:
```
$ dopv undeploy -p  /tmp/pdisks.yaml -d /tmp/pdisks.yaml -r --nodes=foo.bar.baz,/^foo[1-5]\.bar\.baz$/
```
If you'd like to remove all nodes but those matching `foo.bar.baz` as well as nodes that match regular expression `^foo[1-5]\.bar\.baz$` and their data disks, you would use `--exclude_nodes` filter:
```
$ dopv undeploy -p  /tmp/pdisks.yaml -d /tmp/pdisks.yaml -r --exclude_nodes=foo.bar.baz,/^foo[1-5]\.bar\.baz$/
```

#### Logging
By default `dopv` logs messages with `INFO` level and higher to standard output. In order to log to a file `-l` can be specified. The `-v` option is used to set a different log threshold. Following is an example of logging everything (`DEBUG` and above) into `/tmp/dopv.log` during plan deployment:
```
$ dopv -l /tmp/dopv.log -v debug deploy -p /tmp/plan.yaml -d /tmp/disks.yaml
```

## Node Filtering Notes
Please note that `dopv` filtering by configuration and roles is not yet supported.

## Plan
A plan format and description can be found [here](https://gitlab.swisscloud.io/clu-dop/dop_common/blob/master/doc/plan_format_v0.0.1.md). A plan example can be found [here](https://gitlab.swisscloud.io/clu-dop/dop_common/blob/master/doc/examples/example_deploment_plan_v0.0.1.yaml)


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
