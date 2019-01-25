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
  - qemu needs access to this users home directory:
    - `$ chmod 755 ~stack`

# Instructions

## 1) Run the scripts in order

- `./01_install_requirements.sh`
- `./02_configure_host.sh`

This should result in some (stopped) VMs created by tripleo-quickstart on the
local virthost and some other dependencies installed.

- `./03_ocp_repo_sync.sh`
- `./04_build_ocp_installer.sh`

These will pull and build the openshift-install and some other things from
source.

- `05_run_ocp.sh`

This will run the openshift-install to generate ignition configs and boot the
bootstrap VM, currently no cluster is actually created.

## 2) Cleanup

To clean up your environment you can run:

- `./ocp_cleanup.sh`
- `./libvirt_cleanup.sh`
