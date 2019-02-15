MetalKube Installer Dev Scripts
===============================

This set of scripts configures some libvirt VMs and associated
[virtualbmc](https://docs.openstack.org/tripleo-docs/latest/install/environments/virtualbmc.html) processes to enable deploying to them as dummy baremetal nodes.

This is very similar to how we do TripleO testing so we reuse some roles
from tripleo-quickstart here.

# Pre-requisites

- CentOS 7
- ideally on a bare metal host
- run as a user with passwordless sudo access
- get a valid pull secret (json string) from https://cloud.openshift.com/clusters/install#pull-secret

# Instructions

## Configuration

Make a copy of the `config_example.sh` to `config_$USER.sh`, and set the `PULL_SECRET`
variable to the secret obtained from cloud.openshift.com.

For baremetal test setups where you don't require the VM fake-baremetal nodes, you may also
set `NODES_FILE` to reference a manually created json file with the node details, and
`NODES_PLATFORM` which can be set to e.g "baremetal" to disable the libvirt master/worker
node setup. See common.sh for other variables that can be overridden.

## Installation

For a new setup, run:

`make`

The Makefile will run the scripts in this order:

- `./01_install_requirements.sh`
- `./02_configure_host.sh`

This should result in some (stopped) VMs created by tripleo-quickstart on the
local virthost and some other dependencies installed.

- `./03_ocp_repo_sync.sh`

After this step, you can run the [facet](https://github.com/metalkube/facet)
server with:

```
$ go run "${GOPATH}/src/github.com/metalkube/facet/main.go" server
```

- `./04_build_ocp_installer.sh`

These will pull and build the openshift-install and some other things from
source.

- `./05_deploy_bootstrap_vm.sh`

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

- `./06_deploy_masters.sh`

This will deploy the master nodes via ironic, using the Ignition config
generated in the previous step.

For manual debugging via openstackclient, you can use the following:

```
export OS_TOKEN=fake-token
export OS_URL=http://ostest-api.test.metalkube.org:6385/
openstack baremetal node list
...
```

To ssh to the master nodes, you can route trafic through the bootstrap node
```
sudo ip route add 172.22.0.0/24 via $(getent hosts ostest-api.test.metalkube.org | grep 192 | awk '{ print $1 }')
ssh core@ostest-etcd-<n>.test.metalkube.org
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

You can use:

```
virsh console domain_name
```

To get to the bootstrap node. The username is `core` and the password is `notworking`
