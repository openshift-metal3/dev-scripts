MetalKube Installer Dev Scripts
===============================

This set of scripts configures some libvirt VMs and associated
[virtualbmc](https://docs.openstack.org/tripleo-docs/latest/install/environments/virtualbmc.html) processes to enable deploying to them as dummy baremetal nodes.

This is very similar to how we do TripleO testing so we reuse some roles
from tripleo-quickstart here.

# Pre-requisites

- CentOS 7.5 or greater (installed from 7.4 or newer)
- file system that supports d_type (see Troubleshooting section for more information)
- ideally on a bare metal host
- run as a user with passwordless sudo access
- get a valid pull secret (json string) from https://cloud.openshift.com/clusters/install#pull-secret

# Instructions

## Configuration

Make a copy of the `config_example.sh` to `config_$USER.sh`, and set the
`PULL_SECRET` variable to the secret obtained from cloud.openshift.com.

For baremetal test setups where you don't require the VM fake-baremetal nodes,
you may also set `NODES_FILE` to reference a manually created json file with
the node details (see [ironic_hosts.json.example](ironic_hosts.json.example)),
and `NODES_PLATFORM` which can be set to e.g "baremetal" to disable the libvirt
master/worker node setup. See [common.sh](common.sh) for other variables that
can be overridden.

## Installation

For a new setup, run:

`make`

The Makefile will run the scripts in this order:

- `./01_install_requirements.sh`
- `./02_configure_host.sh`

This should result in some (stopped) VMs created by tripleo-quickstart on the
local virthost and some other dependencies installed.

- `./03_ocp_repo_sync.sh`

After this step, you can run the [facet](https://github.com/openshift-metalkube/facet)
server with:

```
$ go run "${GOPATH}/src/github.com/openshift-metalkube/facet/main.go" server
```

- `./04_setup_ironic.sh`

This will setup Ironic on the host server and download the resources it requires

- `./05_build_ocp_installer.sh`

These will pull and build the openshift-install and some other things from
source.

- `./06_deploy_bootstrap_vm.sh`

This will run the openshift-install to generate ignition configs and boot the
bootstrap VM, including a bootstrap ironic all in one container.
Ironic container is stored at https://quay.io/repository/metalkube/metalkube-ironic, built from https://github.com/metalkube/metalkube-ironic
Currently no cluster is actually created.

When the VM is running, the script will show the IP and you can ssh to the
VM via ssh core@IP.

Then you can interact with the k8s API on the bootstrap VM e.g
`sudo oc status --verbose --config /etc/kubernetes/kubeconfig`.

You can also see the status of the bootkube.sh script which is running via
`journalctl -b -f -u bootkube.service`.

- `./07_deploy_masters.sh`

This will deploy the master nodes via ironic, using the Ignition config
generated in the previous step.

After running `./07_deploy_masters.sh` note that it takes some time for the cluster to
fully come up, many container images are downloaded before the k8s API is fully available.

- `./08_deploy_bmo.sh`

After running `./08_deploy_bmo.sh` the cluster that becomes active in the previous step
is updated by deploying the baremetal-operator into the pre-existing "openshift-machine-api"
project/namespace.

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

## Cleanup

- To clean up the ocp deployment run `./ocp_cleanup.sh`

- To clean up the dummy baremetal VMs and associated libvirt resources run `./host_cleanup.sh`

e.g. to clean and re-install ocp run:

```
./ocp_cleanup.sh
rm -fr ocp
./05_run_ocp.sh
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
