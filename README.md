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

## Installation

For a new setup, run:

`make`

The Makefile will run the scripts in this order:

- `./01_install_requirements.sh`
- `./02_configure_host.sh`

This should result in some (stopped) VMs created by tripleo-quickstart on the
local virthost and some other dependencies installed.

- `./03_ocp_repo_sync.sh`
- `./04_build_ocp_installer.sh`

These will pull and build the openshift-install and some other things from
source.

- `./05_run_ocp.sh`

This will run the openshift-install to generate ignition configs and boot the
bootstrap VM, including a bootstrap ironic all in one container,
currently no cluster is actually created.

When the VM is running, the script will show the IP and you can ssh to the
VM via ssh core@IP.

Then you can interact with the k8s API on the bootstrap VM e.g
`sudo oc status --verbose --config /etc/kubernetes/kubeconfig`.

You can also see the status of the bootkube.sh script which is running via
`journalctl -b -f -u bootkube.service`.

## Interact with Ironic from the host

You can test ironic by talking to its API with the openstack client (from the
virt host)

```
export OS_TOKEN=fake-token
export OS_URL=http://ostest-api.test.metalkube.org:6385/
```

To define the master nodes, you can use:

```
openstack baremetal create ocp/master_nodes.json
```

Then to deploy you can do e.g:

```
# Set NODE_UUID to the uuid of the node you want to work with
NODE_UUID=$(openstack baremetal node show openshift-master-0 -f value -c uuid)
openstack baremetal node set $NODE_UUID --instance-info image_source=http://172.22.0.1/images/redhat-coreos-maipo-47.284-openstack.qcow2 --instance-info image_checksum=2a38fafe0b9465937955e4d054b8db3a --instance-info root_gb=25 --property root_device='{"name": "/dev/vda"}'
openstack baremetal node manage $NODE_UUID --wait
openstack baremetal node provide $NODE_UUID --wait
```

And to deploy a node with the cirros image (image\_source above):

```
openstack baremetal node deploy $NODE_UUID
```

## Cleanup

- To clean up the ocp deployment run `./ocp_cleanup.sh`

- To clean up the dummy baremetal VMs and associated libvirt resources run `./libvirt_cleanup.sh`

e.g. to clean and re-install ocp run:

```
./ocp_cleanup.sh
rm -fr ocp
./05_run_ocp.sh
```

Or, you can run `make clean` which will run all of the cleanup steps.

## Troubleshooting
If you're having trouble, try `systemctl restart libvirtd`.

