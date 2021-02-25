Metal³ Installer Dev Scripts
============================

This set of scripts configures some libvirt VMs and associated
[virtualbmc](https://opendev.org/openstack/virtualbmc) processes to enable deploying to them as dummy baremetal nodes.

We are using this repository as a work space for development environment setup
and convenience/test scripts, the main logic needed to enable 
bare metal provisioning is now integrated into the 
[go-based openshift-installer](https://github.com/openshift/installer) and 
other components of OpenShift via support for a baremetal platform type.

# Pre-requisites

- CentOS 8 or RHEL 8 host
- file system that supports d_type (see Troubleshooting section for more information)
- ideally on a bare metal host with at least 64G of RAM
- run as a user with passwordless sudo access
- get a valid pull secret (json string) from https://cloud.redhat.com/openshift/install/pull-secret
- get a login token from https://api.ci.openshift.org
- hostnames for masters and workers must be in the format XX-master-# (e.g. openshift-master-0), or XX-worker-# (e.g. openshift-worker-0)

# Instructions

## Preparation

Considering that this is a new install on a clean OS, the next tasks should be performed prior the installation:

1. Enable passwordless sudo for the current user

    Consider creating a separate user for deployments, one without SSH access.

    `echo "$USER  ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/${USER}`

2. In case of RHEL, invoke `subscription-manager` in order to `register` and `attach` the subscription

3. Install new packages

    ```bash
    sudo dnf upgrade -y
    sudo dnf install -y git make wget jq
    ```

4. Clone the dev-scripts repository

    `git clone https://github.com/openshift-metal3/dev-scripts`

5. Create a config file

    `cp config_example.sh config_$USER.sh`

6. Configure dev-scripts working directory

    By default, dev-scripts' working directory is set to `/opt/dev-scripts`.
    Make sure that the filesystem has at least 80GB of free space: `df -h /`.
    
    Alternatively you may have a large `/home` filesystem,
    in which case you can `export WORKING_DIR=/home/dev-scripts` and the scripts will create this directory with appropriate permissions.
    In the event you create this directory manually it should be world-readable (`chmod 755`) and `chown`ed by the non-root `$USER`.

## Configuration

Make a copy of the `config_example.sh` to `config_$USER.sh`.

Go to https://api.ci.openshift.org, click on your name in the top
right, copy the login command, extract the token from the command and
use it to set `CI_TOKEN` in `config_$USER.sh`.

Save the secret obtained from cloud.openshift.com to
`pull_secret.json`.

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
# Set your default network type, `OpenShiftSDN` or `OVNKubernetes`, defaults to `OpenShiftSDN`
NETWORK_TYPE="OpenShiftSDN"
# Set to the subnet in use on the external (baremetal) network
EXTERNAL_SUBNET_V4="192.168.111.0/24"
# Provide additional master/worker ignition configuration, will be
# merged with the installer provided config, can be used to modify
# the default nic configuration etc
export IGNITION_EXTRA=extra.ign
# Folder where to copy extra manifests for the cluster deployment
export ASSETS_EXTRA_FOLDER=local_file_path
```

## Installation

Consider using `tmux`, `screen` or `nohup` as the installation takes around 1 hour.

For a new setup, run:

`make`

The Makefile will run the scripts in this order:

- `./01_install_requirements.sh`

This installs any prerequisite packages, and also starts a local container registry to enable
subsequent scripts to build/push images for testing.  Any other dependencies for development/test
are also installed here.

- `./02_configure_host.sh`

This does necessary configuration on the host, e.g networking/firewall and
also creates the libvirt resources necessary to deploy on VMs as emulated
baremetal.

This should result in some (stopped) VMs on the local virthost and some
additional bridges/networks for the `baremetal` and `provisioning` networks.

- `./03_build_installer.sh`

This will extract openshift-install from the OCP release payload.

- `./04_setup_ironic.sh`

This will setup containers related to the Ironic deployment services which
run on the bootstrap VM and deployed cluster.  It will start a webserver which
caches the necessary images, starts virtual BMC services to control the VMs
via IPMI or Redfish.

This script also can optionally build/push custom images for Ironic and other
components see the [Testing custom container images](#Testing-custom-container-images) section below.


- `./06_create_cluster.sh`

This will run `openshift-install` to generate ignition configs for the
bootstrap node and the masters.  The installer then launches both the
bootstrap VM and master nodes using the Terraform providers for libvirt
and Ironic.  Once bootstrap is complete, the installer removes the
bootstrap node and the cluster will be online.

You can view the IP for the bootstrap node by running `sudo virsh
net-dhcp-leases ostestbm`.  You can SSH to it using ssh core@IP.

Then you can interact with the k8s API on the bootstrap VM e.g
`sudo oc status --kubeconfig /etc/kubernetes/kubeconfig`.

You can also see the status of the bootkube.sh script which is running via
`journalctl -b -f -u bootkube.service`.

## Interacting with the deployed cluster

Consider `export KUBECONFIG=<path-to-config>` to avoid using the `--kubeconfig` flag on each command.

When the master nodes are up and the cluster is active, you can interact with the API:

```
$ oc --kubeconfig ocp/${CLUSTER_NAME}/auth/kubeconfig get nodes
NAME       STATUS    ROLES     AGE       VERSION
master-0   Ready     master    20m       v1.12.4+50c2f2340a
master-1   Ready     master    20m       v1.12.4+50c2f2340a
master-2   Ready     master    20m       v1.12.4+50c2f2340a
```

### GUI

Alternatively it is possible to manage the cluster using OpenShift Console web UI.
The URL can be retrieved using
```
oc get routes --all-namespaces | grep console
```
By default, the URL is https://console-openshift-console.apps.ostest.test.metalkube.org

Accessing the web Console running on virtualized cluster from local web browser requires additional setup on local machine and the virt host to enable forwarding to cluster's VMs.

There are two ways to achieve this, by using `sshuttle` or `xinetd`.

### sshuttle (works only with IPv4)

1. On your local machine install `sshuttle`
   
2. Add entry to `/etc/hosts`
    
    ```
    192.168.111.4 console-openshift-console.apps.ostest.test.metalkube.org console openshift-authentication-openshift-authentication.apps.ostest.test.metalkube.org api.ostest.test.metalkube.org prometheus-k8s-openshift-monitoring.apps.ostest.test.metalkube.org alertmanager-main-openshift-monitoring.apps.ostest.test.metalkube.org kubevirt-web-ui.apps.ostest.test.metalkube.org oauth-openshift.apps.ostest.test.metalkube.org grafana-openshift-monitoring.apps.ostest.test.metalkube.org
    ```

3. Run sshuttle on the local machine

    ```
    sshuttle -r <user>@<virthost> 192.168.111.0/24
    ```

### xinetd

This approach uses xinetd instead of iptables to allow IPv4 to IPv6 forwarding.

1. Install xinetd

    ```
    sudo yum install xinetd -y
    ```

2. Copy the example config file

    ```
    sudo cp dev-scripts/openshift_xinetd_example.conf /etc/xinetd.d/openshift
    ```

3. Edit the config file

    - The values can be found at `dev-scripts/ocp/.openshift_install_state.json`

    ```
    sudo vim /etc/xinetd.d/openshift
    ```

4. Restart xinetd
   
    ```
    sudo systemctl restart xinetd
    ```

5. Populate your local machine's `/etc/hosts/`

    - Replace `<HOST_IP>` with your host machine's address

    ```
    <HOST_IP> console-openshift-console.apps.ostest.test.metalkube.org openshift-authentication-openshift-authentication.apps.ostest.test.metalkube.org grafana-openshift-monitoring.apps.ostest.test.metalkube.org prometheus-k8s-openshift-monitoring.apps.ostest.test.metalkube.org api.ostest.test.metalkube.org oauth-openshift.apps.ostest.test.metalkube.org
    ```

6.  Ensure that ports 443 and 6443 ports on the host are open

    ```
    sudo firewall-cmd --zone=public --permanent --add-service=https
    sudo firewall-cmd --permanent --add-port=6443/tcp
    sudo firewall-cmd --reload
    ```

Finally, to access the web Console use the `kubeadmin` user, and password generated in the `dev-scripts/ocp/${CLUSTER_NAME}/auth/kubeadmin-password` file.

## Hosting multiple dev-scripts on the same host

dev-scripts has some support for running multiple instances on the
same resources, when doing this CLUSTER\_NAME is used to namespace various
resources on the virtual host. This support is not activly tested and
has a few limitations but aims to allow you to run two separate clusters
on the same host.

To do this a the same user should be used to run dev-scripts for all
environments but with a different config file. In the config file at least
the following 3 environment variables should be defined and differ from
their defaults
CLUSTER\_NAME, PROVISIONING\_NETWORK and EXTERNAL\_SUBNET\_V4 e.g.
```
export CLUSTER_NAME=osopenshift
export PROVISIONING_NETWORK=172.33.0.0/24
export EXTERNAL_SUBNET_V4=192.168.222.0/24
```

Some resources are also shared on the virt hosts (e.g. some of the
container on the virt host serving images, redfish etc..) In order
to avoid multiple environments interfering with each other you
should not clean or deploy one environment while another is deploying

## Interacting with Ironic directly

The `./06_create_cluster.sh` script generates a `clouds.yaml` file with
connection settings for both instances of Ironic. The copy of Ironic
that runs on the bootstrap node during installation can be accessed by
using the cloud name `metal3-bootstrap` and the copy running inside
the cluster once deployment is finished can be accessed by using the
cloud name `metal3`.

Note that the `clouds.yaml` is generated on exit from `./06_create_cluster.sh`
(on success, and also on failure if possible), however it can be useful
to generate the file during deployment, in which case `generate_clouds_yaml.sh`
may be run manually.

The dev-scripts will install the `baremetal` command line tool on the
provisioning host as part of setting up the cluster.  The `baremetal`
tool will look for `clouds.yaml` in the `_clouds_yaml` directory.

For manual debugging via the baremetal client connecting to the bootstrap
VM, which is ephemeral and won't be available once the masters have
been deployed:

```
export OS_CLOUD=metal3-bootstrap
baremetal node list
...
```

To access the Ironic instance running in the baremetal-operator pod:

```
export OS_CLOUD=metal3
baremetal node list
...
```

And to access the Ironic inspector instance running in the baremetal-operator pod:

```
export OS_CLOUD=metal3-inspector
baremetal introspection list
...
```

NOTE: If you use a provisioning network other than the default, you
may need to modify the IP addresses used in

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
variables that override the defaults in metal3-dev-env.

The VM resources can be overridden by setting the follwing environment variables
in `config_$USER.sh`:

```
# Change VM resources for masters
#export MASTER_MEMORY=16384
#export MASTER_DISK=20
#export MASTER_VCPU=8

# Change VM resources for workers
#export WORKER_MEMORY=8192
#export WORKER_DISK=20
#export WORKER_VCPU=4
```

### Testing custom container images
dev-scripts uses an openshift release image that contains references to openshift
containers, any of these containers can be overridden by setting environment
variables of the form `<NAME>_LOCAL_IMAGE` to build or use copy of container
images locally e.g. to use a custom ironic container image and build a container
image from a git repository for the machine-config-operator you could set

```
export IRONIC_LOCAL_IMAGE=quay.io/username/ironic
export MACHINE_CONFIG_OPERATOR_LOCAL_IMAGE=https://github.com/openshift/machine-config-operator
```

The value for `<NAME>` needs to match the name of the tags for images (found in the
openshift release images in /release-manifests/image-references), converted to uppercase
and with "-"'s converted to "_"'s.

### Testing a custom machine-api-operator image with this deployment

The script `run-custom-mao.sh` allows the machine-api-operator pod to be re-deployed with a custom image.

For example:
`./run-custom-mao.sh <path in quay.io for the custom MAO image with tag> <repo name> <branch name>`

Custom MAO image name is a mandatory parameter but the others are optional with defaults.

Alternatively, all input parameters can be set via `CUSTOM_MAO_IMAGE`, `REPO_NAME` and `MAO_BRANCH` variables respectively,
and `run-custom-mao.sh` can be run automatically if you set `TEST_CUSTOM_MAO` to true.

### Testing a customizations to the deployed OS

It is possible to pass additional ignition configuration which will be merged with the installer generated files
prior to deployment.  This can be useful for debug/testing during development, and potentially also for configuration
of networking or storage on baremetal nodes needed before cluster configuration starts (most machine configuration
should use the machine-config-operator, but for changes required before that starts, ignition may be an option).

The following adds an additional file `/etc/test` as an example:

```
export IGNITION_EXTRA="ignition/file_example.ign"
```

### Testing with extra workers

It is possible to specify additional workers, which are not used in the initial
deployment, and can then later be used e.g to test scale-out. The default online
status of the exrea workers is true, but can be changed to false using
EXTRA_WORKERS_ONLINE_STATUS.

```
export NUM_EXTRA_WORKERS=2
export EXTRA_WORKERS_ONLINE_STATUS=false
```

After initial deployment, a file containing the BareMetalHost manifests can be
applied:

```
oc apply -f ocp/ostest/extra_host_manifests.yaml
```

Once completed, it's possibile to scale up the machineset to provision the extra workers.
The following example shows how to add another worker to the current deployment:

```
$ oc get machineset -n openshift-machine-api
NAME              DESIRED   CURRENT   READY   AVAILABLE   AGE
ostest-worker-0   2         2         2       2           27h

$ oc scale machineset ostest-worker-0 --replicas=3 -n openshift-machine-api
machineset.machine.openshift.io/ostest-worker-0 scaled
```

### Deploying dummy remote cluster nodes

It is possible to add remote site nodes along with their own L2 network. To do so, use the 
`create_remote_nodes.sh` script to create the definitions of VMs and their corresponding network.
Additional configuration can be made by altering the environment variables within the script.

Create remote cluster VMs and their network using the `create_remote_nodes.sh` script.
The script accepts an optional namespace argument.  If omitted, the namespace will default
to `openshift-machine-api`.

```
./create_remote_nodes.sh [namespace]
```
