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
