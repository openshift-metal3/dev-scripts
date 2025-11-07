#!/bin/bash
#
# Add a worker node to an existing cluster after deployment
#
# Usage: ./add_worker_node.sh [worker_name]
#
# This script:
# 1. Creates a new libvirt VM
# 2. Configures virtual BMC for the VM
# 3. Generates and applies BareMetalHost manifest
# 4. Provides instructions for scaling the machineset
#

set -euo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source ${SCRIPTDIR}/logging.sh
source ${SCRIPTDIR}/common.sh
source ${SCRIPTDIR}/network.sh
source ${SCRIPTDIR}/utils.sh
source ${SCRIPTDIR}/ocp_install_env.sh

# Parse arguments
WORKER_NAME=${1:-"extraworker-0"}

# Validate worker name format
if [[ ! "$WORKER_NAME" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
    echo "Error: Worker name must be lowercase alphanumeric with hyphens"
    exit 1
fi

# Check if cluster is running
if ! oc get nodes &>/dev/null; then
    echo "Error: Cannot connect to cluster. Ensure your cluster is running and KUBECONFIG is set."
    exit 1
fi

# Check if worker VM already exists
if sudo virsh list --all | grep -q "${CLUSTER_NAME}_${WORKER_NAME}"; then
    echo "Error: VM ${CLUSTER_NAME}_${WORKER_NAME} already exists"
    exit 1
fi

# Check if BareMetalHost already exists
if oc get baremetalhost -n openshift-machine-api "${CLUSTER_NAME}-${WORKER_NAME}" &>/dev/null; then
    echo "Error: BareMetalHost ${CLUSTER_NAME}-${WORKER_NAME} already exists"
    exit 1
fi

echo "=========================================="
echo "Adding worker node: ${WORKER_NAME}"
echo "Cluster: ${CLUSTER_NAME}"
echo "=========================================="

# Generate MAC address
WORKER_MAC=$(printf '52:54:00:%02x:%02x:%02x' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
echo "Generated MAC address: ${WORKER_MAC}"

# Find available BMC port
VBMC_BASE_PORT=${VBMC_BASE_PORT:-6230}
VBMC_MAX_PORT=${VBMC_MAX_PORT:-6250}
BMC_PORT=""

for port in $(seq $VBMC_BASE_PORT $VBMC_MAX_PORT); do
    if ! sudo netstat -tuln | grep -q ":${port} "; then
        BMC_PORT=$port
        break
    fi
done

if [ -z "$BMC_PORT" ]; then
    echo "Error: No available BMC ports in range ${VBMC_BASE_PORT}-${VBMC_MAX_PORT}"
    exit 1
fi

echo "Using BMC port: ${BMC_PORT}"

# Set worker resources
EXTRA_WORKER_MEMORY=${EXTRA_WORKER_MEMORY:-16384}
EXTRA_WORKER_DISK=${EXTRA_WORKER_DISK:-50}
EXTRA_WORKER_VCPU=${EXTRA_WORKER_VCPU:-8}

# Determine BMC driver and protocol
BMC_DRIVER=${BMC_DRIVER:-"redfish-virtualmedia"}
if [[ "$BMC_DRIVER" == "ipmi" ]]; then
    BMC_PROTOCOL="ipmi"
    BMC_ADDRESS="${PROVISIONING_HOST_EXTERNAL_IP}:${BMC_PORT}"
    BMC_FULL_ADDRESS="${BMC_PROTOCOL}://${BMC_ADDRESS}"
elif [[ "$BMC_DRIVER" =~ "redfish" ]]; then
    BMC_PROTOCOL="redfish-virtualmedia"
    BMC_ADDRESS="${PROVISIONING_HOST_EXTERNAL_IP}:8000/${WORKER_NAME}"
    BMC_FULL_ADDRESS="${BMC_PROTOCOL}+http://${BMC_ADDRESS}"
else
    echo "Error: Unsupported BMC driver: ${BMC_DRIVER}"
    exit 1
fi

echo "BMC Address: ${BMC_FULL_ADDRESS}"

# Create VM disk
DISK_PATH="/var/lib/libvirt/images/${CLUSTER_NAME}_${WORKER_NAME}.qcow2"
echo "Creating disk at ${DISK_PATH} (${EXTRA_WORKER_DISK}G)..."
sudo qemu-img create -f qcow2 "${DISK_PATH}" "${EXTRA_WORKER_DISK}G"

# Get the baremetal network details
BAREMETAL_NETWORK=${BAREMETAL_NETWORK_NAME:-"baremetal"}

# Determine firmware and NVRAM paths based on architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        if [ "${LIBVIRT_FIRMWARE:-uefi}" == "uefi" ]; then
            FIRMWARE_PATH="/usr/share/OVMF/OVMF_CODE.fd"
            NVRAM_PATH="/var/lib/libvirt/qemu/nvram/${CLUSTER_NAME}_${WORKER_NAME}_VARS.fd"
            LOADER_TYPE="pflash"
        fi
        ;;
    aarch64)
        if [ "${LIBVIRT_FIRMWARE:-uefi}" == "uefi" ]; then
            FIRMWARE_PATH="/usr/share/AAVMF/AAVMF_CODE.fd"
            NVRAM_PATH="/var/lib/libvirt/qemu/nvram/${CLUSTER_NAME}_${WORKER_NAME}_VARS.fd"
            LOADER_TYPE="pflash"
        fi
        ;;
esac

# Create VM definition
echo "Creating VM ${CLUSTER_NAME}_${WORKER_NAME}..."

VM_XML=$(cat <<EOF
<domain type='kvm'>
  <name>${CLUSTER_NAME}_${WORKER_NAME}</name>
  <memory unit='MiB'>${EXTRA_WORKER_MEMORY}</memory>
  <vcpu placement='static'>${EXTRA_WORKER_VCPU}</vcpu>
  <os>
    <type arch='${ARCH}' machine='q35'>hvm</type>
EOF
)

if [ "${LIBVIRT_FIRMWARE:-uefi}" == "uefi" ]; then
    VM_XML+=$(cat <<EOF

    <loader readonly='yes' type='${LOADER_TYPE}'>${FIRMWARE_PATH}</loader>
    <nvram>${NVRAM_PATH}</nvram>
EOF
)
fi

VM_XML+=$(cat <<EOF

    <boot dev='network'/>
    <boot dev='hd'/>
    <bootmenu enable='no'/>
  </os>
  <features>
    <acpi/>
    <apic/>
  </features>
  <cpu mode='host-passthrough'/>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>destroy</on_crash>
  <devices>
    <emulator>/usr/libexec/qemu-kvm</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='unsafe'/>
      <source file='${DISK_PATH}'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <interface type='network'>
      <mac address='${WORKER_MAC}'/>
      <source network='${BAREMETAL_NETWORK}'/>
      <model type='virtio'/>
    </interface>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <channel type='unix'>
      <target type='virtio' name='org.qemu.guest_agent.0'/>
    </channel>
    <rng model='virtio'>
      <backend model='random'>/dev/urandom</backend>
    </rng>
  </devices>
</domain>
EOF
)

# Define the VM
echo "$VM_XML" | sudo virsh define /dev/stdin

echo "VM created successfully"

# Setup virtual BMC
echo "Configuring virtual BMC..."

if [ "$NODES_PLATFORM" = "libvirt" ]; then
    # Ensure vbmc/sushy-tools are running
    if [ "$BMC_DRIVER" = "ipmi" ]; then
        if ! is_running vbmc; then
            echo "Starting vbmc container..."
            sudo rm -f $WORKING_DIR/virtualbmc/vbmc/master.pid
            sudo podman run -d --net host --privileged --name vbmc --pod ironic-pod \
                 -v "$WORKING_DIR/virtualbmc/vbmc":/root/.vbmc -v "/root/.ssh":/root/ssh \
                 "${VBMC_IMAGE}"
            sleep 5
        fi
        
        # Add vbmc entry
        echo "Adding VBMC entry for ${CLUSTER_NAME}_${WORKER_NAME}..."
        sudo podman exec vbmc vbmc add "${CLUSTER_NAME}_${WORKER_NAME}" \
            --port "${BMC_PORT}" \
            --username "admin" \
            --password "password" \
            --libvirt-uri "qemu+ssh://root@${PROVISIONING_HOST_EXTERNAL_IP}/system?&keyfile=/root/ssh/id_rsa_virt_power&no_verify=1&no_tty=1"
        sudo podman exec vbmc vbmc start "${CLUSTER_NAME}_${WORKER_NAME}"
        
    else  # redfish
        if ! is_running sushy-tools; then
            echo "Starting sushy-tools container..."
            sudo podman run -d --net host --privileged --name sushy-tools --pod ironic-pod \
                 -v "$WORKING_DIR/virtualbmc/sushy-tools":/root/sushy -v "/root/.ssh":/root/ssh \
                 "${SUSHY_TOOLS_IMAGE}"
            sleep 5
        fi
        echo "Sushy-tools will automatically detect the new VM"
    fi
fi

echo "Virtual BMC configured"

# Generate BareMetalHost manifest
BMH_MANIFEST="${OCP_DIR}/${WORKER_NAME}_bmh.yaml"

echo "Generating BareMetalHost manifest at ${BMH_MANIFEST}..."

cat > "${BMH_MANIFEST}" <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: ${CLUSTER_NAME}-${WORKER_NAME}-bmc-secret
  namespace: openshift-machine-api
type: Opaque
data:
  username: $(echo -n "admin" | base64 -w0)
  password: $(echo -n "password" | base64 -w0)
---
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: ${CLUSTER_NAME}-${WORKER_NAME}
  namespace: openshift-machine-api
  labels:
    infraenvs.agent-install.openshift.io: ${CLUSTER_NAME}
spec:
  online: true
  bootMACAddress: ${WORKER_MAC}
  bmc:
    address: ${BMC_FULL_ADDRESS}
    credentialsName: ${CLUSTER_NAME}-${WORKER_NAME}-bmc-secret
    disableCertificateVerification: true
  automatedCleaningMode: disabled
EOF

echo "=========================================="
echo "Worker node configuration complete!"
echo "=========================================="
echo ""
echo "VM Details:"
echo "  Name: ${CLUSTER_NAME}_${WORKER_NAME}"
echo "  MAC: ${WORKER_MAC}"
echo "  Memory: ${EXTRA_WORKER_MEMORY}MB"
echo "  vCPU: ${EXTRA_WORKER_VCPU}"
echo "  Disk: ${EXTRA_WORKER_DISK}GB"
echo "  BMC: ${BMC_FULL_ADDRESS}"
echo ""
echo "Next steps:"
echo ""
echo "1. Apply the BareMetalHost manifest:"
echo "   oc apply -f ${BMH_MANIFEST}"
echo ""
echo "2. Wait for the host to become available:"
echo "   oc get baremetalhost -n openshift-machine-api ${CLUSTER_NAME}-${WORKER_NAME} -w"
echo ""
echo "3. Scale your worker machineset to provision the node:"
echo "   # Get current machinesets"
echo "   oc get machineset -n openshift-machine-api"
echo ""
echo "   # Scale up (adjust replica count as needed)"
echo "   oc scale machineset <machineset-name> --replicas=<current+1> -n openshift-machine-api"
echo ""
echo "4. Monitor the machine creation:"
echo "   oc get machines -n openshift-machine-api -w"
echo ""
echo "5. Approve CSRs when they appear:"
echo "   oc get csr"
echo "   oc adm certificate approve <csr-name>"
echo ""
echo "   Or approve all pending CSRs:"
echo "   oc get csr -o name | xargs oc adm certificate approve"
echo ""
echo "=========================================="

