#!/usr/bin/env bash
set -euxo pipefail

export AGENT_STATIC_IP_NODE0_ONLY=${AGENT_STATIC_IP_NODE0_ONLY:-"false"}
export AGENT_NMSTATE_DHCP=${AGENT_NMSTATE_DHCP:-"false"}

export AGENT_USE_ZTP_MANIFESTS=${AGENT_USE_ZTP_MANIFESTS:-"false"}

export AGENT_USE_APPLIANCE_MODEL=${AGENT_USE_APPLIANCE_MODEL:-"false"}
export AGENT_APPLIANCE_HOTPLUG=${AGENT_APPLIANCE_HOTPLUG:-"false"}
export AGENT_PLATFORM_TYPE=${AGENT_PLATFORM_TYPE:-"baremetal"}
export AGENT_PLATFORM_NAME=${AGENT_PLATFORM_NAME:-"oci"}
export AGENT_ROOT_DEVICE_HINTS=${AGENT_ROOT_DEVICE_HINTS:-""}

export AGENT_BM_HOSTS_IN_INSTALL_CONFIG=${AGENT_BM_HOSTS_IN_INSTALL_CONFIG:-"false"}

export AGENT_MINIMAL_ISO=${AGENT_MINIMAL_ISO:-"false"}

export BOND_CONFIG=${BOND_CONFIG:-"none"}

export ISCSI_NETWORK="iscsi"
export ISCSI_NETWORK_SUBNET=${ISCSI_NETWORK_SUBNET:-"192.168.145"}
export ISCSI_DEVICE_NAME=${ISCSI_DEVICE_NAME:-"/dev/sdb"}

# Image reference for OpenShift-based Appliance Builder.
# See: https://github.com/openshift/appliance
export APPLIANCE_IMAGE=${APPLIANCE_IMAGE:-"quay.io/edge-infrastructure/openshift-appliance:latest"}

# Override command name in case of extraction
export OPENSHIFT_INSTALLER_CMD="openshift-install"

# Location of extra manifests
export EXTRA_MANIFESTS_PATH="${OCP_DIR}/openshift"

# Set required config vars for the http boot server
# The necessary files will be copied to boot-artifacts by the installer for either:
# 1. PXE, when the 'openshift-install agent create pxe-files' command is run
# 2. Minimal ISO, when the 'openshift-install agent create image' command is run and bootArtifacts is set
#    in install-config.yaml, OR
# 3. ISCSI, to contain the iPXE file needed for iSCSI booting
export BOOT_SERVER_DIR=${WORKING_DIR}/boot-artifacts
export PXE_BOOT_FILE=agent.x86_64.ipxe
export BOOT_SERVER_URL=http://$(wrap_if_ipv6 ${PROVISIONING_HOST_EXTERNAL_IP}):${AGENT_BOOT_SERVER_PORT}

# Configure the instances for PXE booting
function agent_pxe_boot() {
    for (( n=0; n<${2}; n++ ))
      do
          name=${CLUSTER_NAME}_${1}_${n}
          sudo virt-xml ${name} --edit target=sda --disk="boot_order=1"
          sudo virt-xml ${name} --edit source=${BAREMETAL_NETWORK_NAME} --network="boot_order=2" --start
      done
}

function getReleaseImage() {
    local releaseImage=${OPENSHIFT_RELEASE_IMAGE}
    if [[ ! -z "${MIRROR_IMAGES}" && "${MIRROR_IMAGES,,}" != "false" ]]; then
        releaseImage="${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}"
    # If not installing from src, let's use the current version from the binary
    elif [ -z "$KNI_INSTALL_FROM_GIT" ]; then
      local openshift_install="$(realpath "${OCP_DIR}/openshift-install")"
      releaseImage=$("${openshift_install}" --dir="${OCP_DIR}" version | grep "release image" | cut -d " " -f 3)      
    fi
    echo ${releaseImage}
}

# External load balancer configuration.
# The following ports are opened in firewalld so that libvirt VMs can communicate with haproxy.
export MACHINE_CONFIG_SERVER_PORT=22623
export KUBE_API_PORT=6443
export INGRESS_ROUTER_PORT=443
export AGENT_NODE0_IPSV6=${AGENT_NODE0_IPSV6:-}

# Modifies the baremetal network to be fully isolated.
export AGENT_ISOLATED_NETWORK=${AGENT_ISOLATED_NETWORK:-"false"}
