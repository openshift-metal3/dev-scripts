Metal³ Installer Dev Scripts
===============================

This set of scripts configures some libvirt VMs and associated
[virtualbmc](https://docs.openstack.org/tripleo-docs/latest/install/environments/virtualbmc.html) processes to enable deploying to them as dummy baremetal nodes.

This is very similar to how we do TripleO testing so we reuse some roles
from tripleo-quickstart here.

We are using this repository as a work space while we figure out what the
installer needs to do for bare metal provisioning. As that logic is ironed out,
we are moving it into the
the [go-based openshift-installer](https://github.com/openshift/installer) or
to other components of OpenShift.

# Pre-requisites

- CentOS 7.5 or greater (installed from 7.4 or newer)
- file system that supports d_type (see Troubleshooting section for more information)
- ideally on a bare metal host
- run as a user with passwordless sudo access
- get a valid pull secret (json string) from https://cloud.openshift.com/clusters/install#pull-secret
- hostnames for masters and workers must be in the format XX-master-# (e.g. openshift-master-0), or XX-worker-# (e.g. openshift-worker-0)

# Instructions

## Configuration

Make a copy of the `config_example.sh` to `config_$USER.sh`, and set the
`PULL_SECRET` variable to the secret obtained from cloud.openshift.com.

There are variable defaults set in both the `common.sh` and the `ocp_install_env.sh`
scripts, which may be important to override for your particular environment. You can
set override values in your `config_$USER.sh` script.

### Baremetal

For baremetal test setups where you don't require the VM fake-baremetal nodes,
you may also set `NODES_FILE` to reference a manually created json file with
the node details (see [ironic_hosts.json.example](ironic_hosts.json.example) -
make sure the ironic nodes names follow the openshift-master-* and openshift-worker-*
format), and `NODES_PLATFORM` which can be set to e.g "baremetal" to disable the libvirt
master/worker node setup. See [common.sh](common.sh) for other variables that
can be overridden.

Important values to consider for override in your `config_$USER.sh` script:
```bash
# Deploy only the masters and no workers
NUM_WORKERS=0
# Indicate that this is a baremetal deployment
NODES_PLATFORM="baremetal"
# Path to your ironic_hosts.json file per the above
NODES_FILE="/root/dev-scripts/ironic_hosts.json"
# Set to the interface used by the baremetal bridge
INT_IF="em2"
# Set to the interface used by the provisioning bridge on the bootstrap host
PRO_IF="em1"
# Set to the interface used as the provisioning interface on the cluster nodes
CLUSTER_PRO_IF="ens1"
# Don't allow the baremetal bridge to be managed by libvirt
MANAGE_BR_BRIDGE="n"
# Set your valid DNS domain
BASE_DOMAIN=your.valid.domain.com
# Set your valid DNS cluster name
# (will be used as ${CLUSTER_NAME}.${BASE_DOMAIN}
CLUSTER_NAME=clustername
# Set your valid DNS VIP, such as 1.1.1.1 for 'ns1.example.com'
DNS_VIP="1.1.1.1"
# Set to the subnet in use on the external (baremetal) network
EXTERNAL_SUBNET="192.168.111.0/24"
```

## Installation

For a new setup, run:

`make`

The Makefile will run the scripts in this order:

- `./01_install_requirements.sh`
- `./02_configure_host.sh`

This should result in some (stopped) VMs created by tripleo-quickstart on the
local virthost and some other dependencies installed.

- `./03_ocp_repo_sync.sh`

- `./04_setup_ironic.sh`

This will setup containers for the Ironic infrastructure on the host
server and download the resources it requires.

The Ironic container is stored at https://quay.io/repository/metalkube/metalkube-ironic, built from
https://github.com/metalkube/metalkube-ironic.

- `./06_create_cluster.sh`

This will extract openshift-install from the OCP release payload and
run `openshift-install` to generate ignition configs for the
bootstrap node and the masters.  The installer then launches both the
bootstrap VM and master nodes using the Terraform providers for libvirt
and Ironic.  Once bootstrap is complete, the installer removes the
bootstrap node and the cluster will be online.

You can view the IP for the bootstrap node by running `virsh
net-dhcp-leases baremetal`.  You can SSH to it using ssh core@IP.

Then you can interact with the k8s API on the bootstrap VM e.g
`sudo oc status --verbose --config /etc/kubernetes/kubeconfig`.

You can also see the status of the bootkube.sh script which is running via
`journalctl -b -f -u bootkube.service`.

## Interacting with the deployed cluster

When the master nodes are up and the cluster is active, you can interact with the API:

```
$ oc --config ocp/auth/kubeconfig get nodes
NAME       STATUS    ROLES     AGE       VERSION
master-0   Ready     master    20m       v1.12.4+50c2f2340a
master-1   Ready     master    20m       v1.12.4+50c2f2340a
master-2   Ready     master    20m       v1.12.4+50c2f2340a
```

## Interacting with Ironic directly

For manual debugging via openstackclient, you can use the following:

```
export OS_TOKEN=fake-token
export OS_URL=http://localhost:6385/
openstack baremetal node list
...
```

Note that after deployment of the master nodes, some ironic services (particularly dnsmasq) are stopped on the host and Ironic is then available running inside the baremetal operator pod on the cluster.  To access this instance of Ironic export the following OS_URL:

```
export OS_URL=http://172.22.0.3:6385
```

This references the provisioning network IP on the master node that is running the baremetal-operator pod.

## Cleanup

- To clean up the ocp deployment run `./ocp_cleanup.sh`

- To clean up the dummy baremetal VMs and associated libvirt resources run `./host_cleanup.sh`

e.g. to clean and re-install ocp run:

```
./ocp_cleanup.sh
rm -fr ocp
./06_create_cluster.sh
```

Or, you can run `make clean` which will run all of the cleanup steps.

## Troubleshooting
If you're having trouble, try `systemctl restart libvirtd`.

You can use:

```
virsh console domain_name
```

To get to the bootstrap node. The username is `core` and the password is `notworking`

### Determining your filesystem type
If you're not sure what filesystem you have, try `df - T` and the second
column will include the type.

### Determining if your filesystem supports d_type
If the above command returns ext4 or btrfs, d_type is supported by default. If not,
at the command line, try:
```
xfs_info /mount-point
```
If you see `ftype=1` then you have d_type support.

### Modifying cpu/memory/disk resources
The default cpu/memory/disk resources when using virtual machines are provided
by the [vm_setup_vars.yml](vm_setup_vars.yml) file, which sets some dev-scripts
variables that override the defaults in metal3-dev-env
