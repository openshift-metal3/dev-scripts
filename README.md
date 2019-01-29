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

When the VM is running, the script will show the IP and you can ssh to the
VM via ssh core@IP.

You can then add the IP to the /etc/hosts on the node with the hostname,
e.g `sudo echo "192.168.122.235 ostest-api.test.metalkube.org" >> /etc/hosts`.

Then you can interact with the k8s API on the bootstrap VM e.g
`sudo oc status --verbose --config /etc/kubernetes/kubeconfig`.

You can also see the status of the bootkube.sh script which is running via
`journalctl -b -f -u bootkube.service`.

## 2) Cleanup

To clean up your environment you can run:

- `./ocp_cleanup.sh`
- `./libvirt_cleanup.sh`
