# Configuration Presets and Options

## Defining the OpenShift Cluster Topology

OpenShift clusters can have different topologies. In OpenShift development we refer to
these different topologies as different installations with adjectives and acronyms.
Below is the list of cluster topologies currently being used to test the installers:

|                       | Master Nodes | Worker Nodes | Masters Schedulable |
|-----------------------|--------------|--------------|---------------------|
| High Availablity (HA) |       3+     |       2+     |         No          |
| Compact               |       3      |       0      |         Yes         |
| Single Node OpenShift |       1      |       0      |         Yes         |


In the tables below are the dev-scripts defined environment variables and the suggested
values to to achieve the above cluster topologies.
### Minimum Cluster Resources

|                     | Default | High Availablity (HA) | Compact | Single Node OpenShift (SNO) |
|---------------------|:-------:|-----------------------|---------|-----------------------------|
| NUM_MASTERS         |    3    |           3+          |    3    |              1              |
| NUM_WORKERS         |    2    |           2+          |    0    |              0              |
| NUM_EXTRA_WORKERS   |    0    |           0           |    0    |              0              |
| MASTER_MEMORY       |  16384  |         16384         |  16384  |            16384            |
| MASTER_DISK         |    30   |           30          |    30   |              30             |
| MASTER_VCPU         |    8    |           8           |    8    |              8              |
| WORKER_MEMORY       |   8192  |          8192         |         |                             |
| WORKER_DISK         |    30   |           30          |         |                             |
| WORKER_VCPU         |    4    |           4           |         |                             |
| EXTRA_WORKER_MEMORY |   8192  |          8192         |         |                             |
| EXTRA_WORKER_DISK   |    30   |           30          |         |                             |
| EXTRA_WORKER_VCPU   |    4    |           4           |         |                             |

### Recommended Cluster Resources

|                     | Default | High Availablity (HA) | Compact | Single Node OpenShift (SNO) |
|---------------------|:-------:|:---------------------:|:-------:|:---------------------------:|
| NUM_MASTERS         |    3    |           3+          |    3    |              1              |
| NUM_WORKERS         |    2    |           2+          |    0    |              0              |
| NUM_EXTRA_WORKERS   |    0    |           0           |    0    |              0              |
| MASTER_MEMORY       |  16384  |         16384         |  16384  |            32768            |
| MASTER_DISK         |    30   |          120          |   120   |             120             |
| MASTER_VCPU         |    8    |           8           |    8    |              8              |
| WORKER_MEMORY       |   8192  |         16384         |         |                             |
| WORKER_DISK         |    30   |          120          |         |                             |
| WORKER_VCPU         |    4    |           4           |         |                             |
| EXTRA_WORKER_MEMORY |   8192  |         16384         |         |                             |
| EXTRA_WORKER_DISK   |    30   |          120          |         |                             |
| EXTRA_WORKER_VCPU   |    4    |           4           |         |                             |

## Defining the Network Topology

The different network topologies we currently use while testing OpenShift installations are defined below.

### IP Stack

|                        |          Default          |       IPv4       |            IPv6           |       IP Dual-stack       |
|------------------------|:-------------------------:|:----------------:|:-------------------------:|:-------------------------:|
| IP_STACK               |             v6            |        v4        |             v6            |            v4v6           |
| NETWORK_TYPE           |       OVNKubernetes       |   OpenShiftSDN   |       OVNKubernetes       |       OVNKubernetes       |
| CLUSTER_SUBNET_V4      |                           |   10.128.0.0/14  |                           |       10.128.0.0/14       |
| CLUSTER_SUBNET_V6      |         fd01::/48         |                  |         fd01::/48         |         fd01::/48         |
| CLUSTER_HOST_PREFIX_V4 |                           |        23        |                           |             23            |
| CLUSTER_HOST_PREFIX_V6 |             64            |                  |             64            |             64            |
| SERVICE_SUBNET_V4      |                           |                  |                           |       172.30.0.0/16       |
| SERVICE_SUBNET_V6      |         fd02::/112        |                  |         fd02::/112        |         fd02::/112        |
| MIRROR_IMAGES[1]       |            true           |                  |            true           |            true           |
| HOST_IP_STACK[2]       |             v6            |        v4        |             v6            |            v4v6           |
| PROVISIONING_NETWORK   |      fd00:1101::0/64      |   172.22.0.0/24  |      fd00:1101::0/64      |      fd00:1101::0/64      |
| EXTERNAL_SUBNET_V4     |                           | 192.168.111.0/24 |                           |      192.168.111.0/24     |
| EXTERNAL_SUBNET_V6     | fd2e:6f44:5dd8:c956::/120 |                  | fd2e:6f44:5dd8:c956::/120 | fd2e:6f44:5dd8:c956::/120 |

* [1]: MIRROR_IMAGES is unset unless except in the case of IPv6. The true default value of MIRROR_IMAGES is that it is unset.
* [2]: If HOST_IP_STACK is not set then the value is equal to the value of IP_STACK.

### Static IP vs DHCP

TODO(lranjbar): Currently this seems to be only set in our Agent flows for generating static IP. (?)

### Connected vs Disconnected

By default all clusters created by dev-scripts are connected clusters. Meaning the cluster is
connected to the greater internet. In order to simulate a disconnected cluster installation we first
create a local mirrored image registry the same way a customer would in disconnected installation.

Currently quay.io does not support IPv6. So these IPv6 installations are disconnected since we have to
create a local IPv6 mirrored image registry.

|                 | Default | Connected | Disconnected |
|-----------------|:-------:|:---------:|:------------:|
| MIRROR_IMAGES   |         |           |     true     |
| INSTALLER_PROXY |         |           |     true     |

* The defaults for both MIRROR_IMAGES and INSTALLER_PROXY is that these variables are unset.

When setting the above variables to true you also might want to set the following variables:

|                         |                    Default                      | Expected Value          |                                Description                               |
|-------------------------|:-----------------------------------------------:|-------------------------|:------------------------------------------------------------------------:|
| ENABLE_LOCAL_REGISTRY   |                                                 | true                    | Ensure that the local registry will be available.                        |
| LOCAL_REGISTRY_DNS_NAME | virthost.$CLUSTER_NAME.test.metalkube.org       | String - Web domain     | Local image registry DNS name.                                           |
| LOCAL_REGISTRY_PORT     | 5000                                            | String - Port Number    | Local image registry port.                                               |
| REGISTRY_USER           | ocp-user                                        | String                  | Local image registry user.                                               |
| REGISTRY_PASS           | ocp-pass                                        | String                  | Local image registry user's password.                                    |
| REGISTRY_DIR            | $WORKING_DIR/registry                           | String - Directory path | Base directory for the local image registry.                             |
| REGISTRY_CREDS          | $HOME/$USER-private-mirror-$CLUSTER_NAME.json   | String - File path      | Location of the local registry mirror's credentials.                     |
| MIRROR_OLM              |                                                 | String - List           | Comma-separated list of OLM operators to mirror into the local registry. |
| MIRROR_OLM_REMOTE_INDEX | registry.redhat.io/redhat/redhat-operator-index | String                  | Custom operator index image.                                             |
| MIRROR_CUSTOM_IMAGES    |                                                 | String - List           | Comma-separated list of container images to mirror.                      |
