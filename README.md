MetalKube Installer Dev Scripts
===============================

This set of scripts configures some libvirt VMs and associated
[virtualbmc](https://docs.openstack.org/tripleo-docs/latest/install/environments/virtualbmc.html) processes to enable deploying to them as dummy baremetal nodes.

This is very similar to how we do TripleO testing so we reuse some roles
from tripleo-quickstart here.

# Pre-requisites

- CentOS 7
- ideally on a bare metal host
- run as user 'stack' with passwordless sudo access

# Instructions

## 1) Run the scripts in order

- `./01_install_requirements.sh`
- `./02_configure_host.sh`

This should result in some VMs created by tripleo-quickstart on the
local virthost.

All other scripts are WIP and currently under development.

## 2) Cleanup

To clean up you can run:

- `./libvirt_cleanup.sh`
