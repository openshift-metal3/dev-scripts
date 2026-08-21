#!/bin/bash
#
# Remove a worker node from the cluster
#
# Usage: ./remove_worker_node.sh <worker_name>
#
# This script:
# 1. Deletes the BareMetalHost from the cluster
# 2. Deletes the corresponding Machine (if exists)
# 3. Removes the VM and its BMC configuration
# 4. Cleans up disk and NVRAM files
#

set -euo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source ${SCRIPTDIR}/logging.sh
source ${SCRIPTDIR}/common.sh
source ${SCRIPTDIR}/network.sh
source ${SCRIPTDIR}/utils.sh
source ${SCRIPTDIR}/ocp_install_env.sh

# Parse arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <worker_name>"
    echo "Example: $0 extraworker-0"
    exit 1
fi

WORKER_NAME=$1

echo "=========================================="
echo "Removing worker node: ${WORKER_NAME}"
echo "Cluster: ${CLUSTER_NAME}"
echo "=========================================="

# Check if cluster is accessible
if ! oc get nodes &>/dev/null; then
    echo "Warning: Cannot connect to cluster. Will only clean up local resources."
    CLUSTER_ACCESSIBLE=false
else
    CLUSTER_ACCESSIBLE=true
fi

# Delete BareMetalHost
if [ "$CLUSTER_ACCESSIBLE" = true ]; then
    BMH_NAME="${CLUSTER_NAME}-${WORKER_NAME}"
    if oc get baremetalhost -n openshift-machine-api "$BMH_NAME" &>/dev/null; then
        echo "Deleting BareMetalHost ${BMH_NAME}..."
        oc delete baremetalhost -n openshift-machine-api "$BMH_NAME" || true
        
        # Also delete the secret
        SECRET_NAME="${BMH_NAME}-bmc-secret"
        if oc get secret -n openshift-machine-api "$SECRET_NAME" &>/dev/null; then
            echo "Deleting secret ${SECRET_NAME}..."
            oc delete secret -n openshift-machine-api "$SECRET_NAME" || true
        fi
    else
        echo "BareMetalHost ${BMH_NAME} not found in cluster"
    fi
    
    # Check for and delete corresponding Machine
    echo "Checking for Machine resources..."
    MACHINES=$(oc get machine -n openshift-machine-api -o name | grep -i "$WORKER_NAME" || true)
    if [ -n "$MACHINES" ]; then
        echo "Found machines: $MACHINES"
        echo "$MACHINES" | xargs -r oc delete -n openshift-machine-api || true
    fi
    
    # Check for and drain the node if it exists
    if oc get node "${CLUSTER_NAME}-${WORKER_NAME}" &>/dev/null; then
        echo "Draining node ${CLUSTER_NAME}-${WORKER_NAME}..."
        oc adm drain "${CLUSTER_NAME}-${WORKER_NAME}" --ignore-daemonsets --delete-emptydir-data --force || true
        echo "Deleting node ${CLUSTER_NAME}-${WORKER_NAME}..."
        oc delete node "${CLUSTER_NAME}-${WORKER_NAME}" || true
    fi
fi

# Stop and destroy VM
VM_NAME="${CLUSTER_NAME}_${WORKER_NAME}"
if sudo virsh list --all | grep -q "$VM_NAME"; then
    echo "Stopping VM ${VM_NAME}..."
    sudo virsh destroy "$VM_NAME" 2>/dev/null || true
    echo "Undefining VM ${VM_NAME}..."
    sudo virsh undefine "$VM_NAME" --nvram 2>/dev/null || true
else
    echo "VM ${VM_NAME} not found"
fi

# Remove vbmc entry if using IPMI
if [ "${BMC_DRIVER:-redfish-virtualmedia}" = "ipmi" ]; then
    if is_running vbmc; then
        echo "Removing vbmc entry for ${VM_NAME}..."
        sudo podman exec vbmc vbmc delete "$VM_NAME" 2>/dev/null || true
    fi
fi

# Remove disk file
DISK_PATH="/var/lib/libvirt/images/${VM_NAME}.qcow2"
if [ -f "$DISK_PATH" ]; then
    echo "Removing disk ${DISK_PATH}..."
    sudo rm -f "$DISK_PATH"
else
    echo "Disk ${DISK_PATH} not found"
fi

# Remove NVRAM file
NVRAM_PATH="/var/lib/libvirt/qemu/nvram/${VM_NAME}_VARS.fd"
if [ -f "$NVRAM_PATH" ]; then
    echo "Removing NVRAM ${NVRAM_PATH}..."
    sudo rm -f "$NVRAM_PATH"
fi

# Remove manifest file if it exists
BMH_MANIFEST="${OCP_DIR}/${WORKER_NAME}_bmh.yaml"
if [ -f "$BMH_MANIFEST" ]; then
    echo "Removing manifest ${BMH_MANIFEST}..."
    rm -f "$BMH_MANIFEST"
fi

echo "=========================================="
echo "Worker node ${WORKER_NAME} removed successfully"
echo "=========================================="

