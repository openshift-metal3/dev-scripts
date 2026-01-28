# Adding Worker Nodes Post-Installation

This guide explains how to add worker nodes to your cluster **after** the initial deployment is complete using the standard installer flow.

## Overview

The `add_worker_node.sh` script allows you to dynamically add worker nodes to an existing cluster without requiring `NUM_EXTRA_WORKERS` to be set before initial deployment.

The script handles:
- Creating a new libvirt VM with appropriate resources
- Configuring virtual BMC (vbmc or sushy-tools)
- Generating BareMetalHost and Secret manifests
- Providing step-by-step instructions for cluster integration

## Prerequisites

- Cluster must be deployed and accessible (`oc` commands work)
- Virtual BMC containers (vbmc or sushy-tools) should be running (automatically started if needed)
- Sufficient system resources for additional VMs

## Usage

### Adding a Worker Node

#### Option 1: Using the script directly

```bash
./add_worker_node.sh [worker_name]
```

If no name is provided, defaults to `extraworker-0`.

**Example:**
```bash
./add_worker_node.sh my-worker-1
```

#### Option 2: Using Make

```bash
make add_worker WORKER_NAME=my-worker-1
```

### Configuration

You can customize the worker resources by setting environment variables before running the script:

```bash
export EXTRA_WORKER_MEMORY=32768  # Memory in MB (default: 16384)
export EXTRA_WORKER_DISK=100      # Disk size in GB (default: 50)
export EXTRA_WORKER_VCPU=16       # Number of vCPUs (default: 8)
export BMC_DRIVER=ipmi            # BMC driver type (default: redfish-virtualmedia)

./add_worker_node.sh my-large-worker
```

### Post-Script Steps

After running the script, follow these steps to complete the worker addition:

#### 1. Apply the BareMetalHost Manifest

```bash
oc apply -f ocp/ostest/<worker_name>_bmh.yaml
```

#### 2. Wait for Host to Become Available

```bash
oc get baremetalhost -n openshift-machine-api -w
```

Wait until the new BareMetalHost shows `STATE: available`.

#### 3. Scale the Worker MachineSet

```bash
# List current machinesets
oc get machineset -n openshift-machine-api

# Scale up (increment the replica count)
oc scale machineset <cluster-name>-worker-0 --replicas=<current+1> -n openshift-machine-api
```

**Example:**
```bash
$ oc get machineset -n openshift-machine-api
NAME              DESIRED   CURRENT   READY   AVAILABLE   AGE
ostest-worker-0   2         2         2       2           5h

$ oc scale machineset ostest-worker-0 --replicas=3 -n openshift-machine-api
machineset.machine.openshift.io/ostest-worker-0 scaled
```

#### 4. Monitor Machine and Node Creation

```bash
# Watch machines
oc get machines -n openshift-machine-api -w

# Watch nodes
oc get nodes -w
```

#### 5. Approve Certificate Signing Requests (CSRs)

When the node boots and starts joining, it will create CSRs that need approval.

**Manual approval:**
```bash
# Check for pending CSRs
oc get csr

# Approve each CSR
oc adm certificate approve <csr-name>
```

**Auto-approval (convenient for testing):**
```bash
# Auto-approve CSRs for 30 minutes
./auto_approve_csrs.sh 30
```

#### 6. Verify Node is Ready

```bash
oc get nodes
```

You should see your new worker node in the `Ready` state.

## Removing a Worker Node

To remove a worker node that was added:

```bash
./remove_worker_node.sh <worker_name>
```

Or using Make:
```bash
make remove_worker WORKER_NAME=my-worker-1
```

This will:
1. Drain and delete the node from the cluster
2. Delete the BareMetalHost and Secret
3. Delete the corresponding Machine
4. Destroy the VM and clean up disk/NVRAM files
5. Remove BMC configuration

**Note:** Remember to scale down your machineset after removing workers:
```bash
oc scale machineset <machineset-name> --replicas=<current-1> -n openshift-machine-api
```

## Complete Example Workflow

```bash
# 1. Add a new worker
./add_worker_node.sh worker-extra-1

# 2. Apply the manifest
oc apply -f ocp/ostest/worker-extra-1_bmh.yaml

# 3. Wait for it to be available
oc get bmh -n openshift-machine-api -w
# (Ctrl+C when status is 'available')

# 4. Start auto-approving CSRs in background
./auto_approve_csrs.sh 30 &

# 5. Scale the machineset
oc get machineset -n openshift-machine-api
oc scale machineset ostest-worker-0 --replicas=3 -n openshift-machine-api

# 6. Watch the node join
oc get nodes -w

# Done! The worker should be ready in 10-15 minutes
```

## Troubleshooting

### VM Won't Boot

Check VM status:
```bash
sudo virsh list --all
sudo virsh start <cluster-name>_<worker-name>
```

Check VM console:
```bash
sudo virsh console <cluster-name>_<worker-name>
```

### BareMetalHost Stuck in "Registering"

Check BMC connectivity:
```bash
# For IPMI
ipmitool -I lanplus -H <bmc-address> -U admin -P password power status

# Check BMC logs
oc logs -n openshift-machine-api deployment/metal3 -c baremetal-operator
```

### CSRs Not Appearing

Check that the node is booting and has network connectivity:
```bash
# Check DHCP leases
sudo virsh net-dhcp-leases baremetal

# Check VM is running
sudo virsh list --all
```

### BareMetalHost Shows "available" but Machine Won't Create

Check machineset events:
```bash
oc describe machineset <machineset-name> -n openshift-machine-api
```

Ensure you have available BareMetalHosts:
```bash
oc get baremetalhost -n openshift-machine-api
```

## Architecture Notes

- **BMC Drivers**: The script supports both `ipmi` (via vbmc) and `redfish-virtualmedia` (via sushy-tools)
- **Default**: `redfish-virtualmedia` is used by default as it's more modern and feature-rich
- **Port Allocation**: The script automatically finds available BMC ports
- **MAC Generation**: MAC addresses are randomly generated to avoid conflicts
- **Firmware**: Supports both BIOS and UEFI boot modes based on your `LIBVIRT_FIRMWARE` setting

## Limitations

- Only works with libvirt-based deployments
- Requires the provisioning host to have connectivity to libvirt
- BMC port range is limited (default: 6230-6250)
- Worker resources are uniform (all workers use the same resource settings)

## See Also

- [Agent-based Add Nodes](../agent/docs/add-nodes.md) - For agent installer deployments
- [Remote Nodes](../README.md#deploying-dummy-remote-cluster-nodes) - For adding nodes on separate networks

