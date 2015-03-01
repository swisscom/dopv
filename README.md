Dopv

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
```ruby
require 'dopv'
plan = Dopv::Plan.load('plan_file', 'disk_db_file')
plan.execute
```

### CLI
A command line interface utility `dopv` is provided.

#### Getting help
A help can be obtained by calling `dopv -h`:
```
$ dopv -h
Usage: dopv [options]
    -p, --plan FILE                  Specify a plan file to execute
    -d, --disk-db FILE               Specify disk state file
    -l, --log-file FILE              Specify log file (by default standard output)
    -v, --log-level LEVEL            Specify a minimal log level to log
                                     (can be one of debug, info - the default, warning, error)
    -t, --trace                      Show back traces on errors
    -h, --help                       Display help

```

#### Deploying a plan
To deploy a plan located at `/tmp/plan.yaml` while using persistent disks database located at `/tmp/pdisks.yaml` one can launch `dopv` with following options:
```
$ dopv -p  /tmp/pdisks.yaml -d /tmp/pdisks.yaml
```
Please note that disk database file is created if it does not exist.

#### Logging
By default `dopv` logs messages with `INFO` level and higher to standard output. In order to log to a file `-l` can be specified. The `-v` option is used to set a different log threshold. Following is an example of logging everything (`DEBUG` and above) into `/tmp/dopv.log`:
```
$ dopv -p  /tmp/pdisks.yaml -d /tmp/pdisks.yaml -l /tmp/dopv.log -v debug
```

## Plan
A plan format and description can be found [here](https://gitlab.swisscloud.io/clu-dop/dop_common/blob/master/doc/plan_format_v0.0.1.md). A plan example can be found [here](https://gitlab.swisscloud.io/clu-dop/dop_common/blob/master/doc/examples/example_deploment_plan_v0.0.1.yaml)


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
