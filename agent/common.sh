#!/usr/bin/env bash
set -euxo pipefail

export AGENT_STATIC_IP_NODE0_ONLY=${AGENT_STATIC_IP_NODE0_ONLY:-"false"}
export AGENT_NMSTATE_DHCP=${AGENT_NMSTATE_DHCP:-"false"}

export AGENT_USE_ZTP_MANIFESTS=${AGENT_USE_ZTP_MANIFESTS:-"false"}

export AGENT_USE_APPLIANCE_MODEL=${AGENT_USE_APPLIANCE_MODEL:-"false"}
export AGENT_APPLIANCE_HOTPLUG=${AGENT_APPLIANCE_HOTPLUG:-"false"}
export AGENT_PLATFORM_TYPE=${AGENT_PLATFORM_TYPE:-"baremetal"}
export AGENT_PLATFORM_NAME=${AGENT_PLATFORM_NAME:-"oci"}

export AGENT_BM_HOSTS_IN_INSTALL_CONFIG=${AGENT_BM_HOSTS_IN_INSTALL_CONFIG:-"false"}

export BOND_CONFIG=${BOND_CONFIG:-"none"}

# Image reference for OpenShift-based Appliance Builder.
# See: https://github.com/openshift/appliance
export APPLIANCE_IMAGE=${APPLIANCE_IMAGE:-"quay.io/edge-infrastructure/openshift-appliance:latest"}

# Override command name in case of extraction
export OPENSHIFT_INSTALLER_CMD="openshift-install"

# Location of extra manifests
export EXTRA_MANIFESTS_PATH="${OCP_DIR}/openshift"

# Set required config vars for PXE boot mode
if [[ "${AGENT_E2E_TEST_BOOT_MODE}" == "PXE" ]]; then
  export PXE_SERVER_DIR=${WORKING_DIR}/boot-artifacts
  export PXE_SERVER_URL=http://$(wrap_if_ipv6 ${PROVISIONING_HOST_EXTERNAL_IP}):${AGENT_PXE_SERVER_PORT}
  export PXE_BOOT_FILE=agent.x86_64.ipxe
fi

function getReleaseImage() {
    local releaseImage=${OPENSHIFT_RELEASE_IMAGE}
    if [ ! -z "${MIRROR_IMAGES}" ]; then
        releaseImage="${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}"
    # If not installing from src, let's use the current version from the binary
    elif [ -z "$KNI_INSTALL_FROM_GIT" ]; then
      local openshift_install="$(realpath "${OCP_DIR}/openshift-install")"
      releaseImage=$("${openshift_install}" --dir="${OCP_DIR}" version | grep "release image" | cut -d " " -f 3)      
    fi
    echo ${releaseImage}
}

# Functions used to determine IP addresses, MACs, and hostnames
function add_ip_host_entry {
    ip=${1}
    hostname=${2}

    echo "${ip} ${hostname}">>"${OCP_DIR}"/hosts
}

function add_dns_entry {
    ip=${1}
    hostname=${2}

    # Add a DNS entry for this hostname if it's not already defined
    if ! $(sudo virsh net-dumpxml ${BAREMETAL_NETWORK_NAME} | xmllint --xpath "//dns/host[@ip = '${ip}']" - &> /dev/null); then
      sudo virsh net-update ${BAREMETAL_NETWORK_NAME} add dns-host  "<host ip='${ip}'> <hostname>${hostname}</hostname> </host>"  --live --config
    fi

    # Add entries to etc/hosts for SNO IPV6 to sucessfully run the openshift conformance tests
    if [[ $NUM_MASTERS == 1 && $IP_STACK == "v6" ]]; then
      AGENT_NODE0_IPSV6=${ip}
      echo "${ip} console-openshift-console.apps.${CLUSTER_DOMAIN}" | sudo tee -a /etc/hosts
      echo "${ip} oauth-openshift.apps.${CLUSTER_DOMAIN}" | sudo tee -a /etc/hosts
      echo "${ip} thanos-querier-openshift-monitoring.apps.${CLUSTER_DOMAIN}" | sudo tee -a /etc/hosts
    fi
}

function get_static_ips_and_macs() {

    AGENT_NODES_IPS=()
    AGENT_NODES_IPSV6=()
    AGENT_NODES_MACS=()
    AGENT_NODES_HOSTNAMES=()

    if [[ "$AGENT_STATIC_IP_NODE0_ONLY" = "true" ]]; then
        static_ips=1
    else
        static_ips=$NUM_MASTERS+$NUM_WORKERS
    fi

    if [[ $NETWORKING_MODE == "DHCP" ]]; then
      base_ip=20
    else
      # Set outside the range used for dhcp
      base_ip=80
    fi

    for (( i=0; i<${static_ips}; i++ ))
    do
        if [[ $i < $NUM_MASTERS ]]; then
            AGENT_NODES_HOSTNAMES+=($(printf ${MASTER_HOSTNAME_FORMAT} ${i}))
            cluster_name=${CLUSTER_NAME}_master_${i}
        else
	          worker_num=$((${i}-$NUM_MASTERS))
            AGENT_NODES_HOSTNAMES+=($(printf ${WORKER_HOSTNAME_FORMAT} ${worker_num}))
            cluster_name=${CLUSTER_NAME}_worker_${worker_num}
        fi

        ip=${base_ip}+${i}
        if [[ "$IP_STACK" = "v4" ]]; then
            AGENT_NODES_IPS+=($(nth_ip ${EXTERNAL_SUBNET_V4} ${ip}))
            add_dns_entry ${AGENT_NODES_IPS[i]} ${AGENT_NODES_HOSTNAMES[i]}
            add_ip_host_entry ${AGENT_NODES_IPS[i]} ${AGENT_NODES_HOSTNAMES[i]}
        elif [[ "$IP_STACK" = "v6" ]]; then
            AGENT_NODES_IPSV6+=($(nth_ip ${EXTERNAL_SUBNET_V6} ${ip}))
            add_dns_entry ${AGENT_NODES_IPSV6[i]} ${AGENT_NODES_HOSTNAMES[i]}
            add_ip_host_entry ${AGENT_NODES_IPSV6[i]} ${AGENT_NODES_HOSTNAMES[i]}
        else
	          # v4v6
            AGENT_NODES_IPS+=($(nth_ip ${EXTERNAL_SUBNET_V4} ${ip}))
            AGENT_NODES_IPSV6+=($(nth_ip $EXTERNAL_SUBNET_V6 ${ip}))
            add_dns_entry ${AGENT_NODES_IPS[i]} ${AGENT_NODES_HOSTNAMES[i]}
            add_ip_host_entry ${AGENT_NODES_IPS[i]} ${AGENT_NODES_HOSTNAMES[i]}
            add_dns_entry ${AGENT_NODES_IPSV6[i]} ${AGENT_NODES_HOSTNAMES[i]}
        fi

        # Get the generated mac addresses
        AGENT_NODES_MACS+=($(sudo virsh dumpxml $cluster_name | xmllint --xpath "string(//interface[descendant::source[@bridge = '${BAREMETAL_NETWORK_NAME}']]/mac/@address)" -))
        if [[ ! -z "${BOND_PRIMARY_INTERFACE:-}" ]]; then
	        # For a bond, a random mac is added for the 2nd interface
	        AGENT_NODES_MACS+=($(sudo virsh domiflist ${cluster_name} | grep ${BAREMETAL_NETWORK_NAME} | grep -v ${AGENT_NODES_MACS[-1]} | awk '{print $5}'))
        fi
    done

    AGENT_EXTRA_WORKERS_IPS=()
    AGENT_EXTRA_WORKERS_IPSV6=()
    AGENT_EXTRA_WORKERS_MACS=()
    AGENT_EXTRA_WORKERS_HOSTNAMES=()
    extra_workers=$NUM_EXTRA_WORKERS
    for (( i=0; i<${extra_workers}; i++ ))
    do
      AGENT_EXTRA_WORKERS_HOSTNAMES+=($(printf ${EXTRA_WORKER_HOSTNAME_FORMAT} ${i}))
      cluster_name=${CLUSTER_NAME}_extraworker_${i}


      ip=${base_ip}+${static_ips}+${i}
      if [[ "$IP_STACK" = "v4" ]]; then
          AGENT_EXTRA_WORKERS_IPS+=($(nth_ip ${EXTERNAL_SUBNET_V4} ${ip}))
          add_dns_entry ${AGENT_EXTRA_WORKERS_IPS[i]} ${AGENT_EXTRA_WORKERS_HOSTNAMES[i]}
          add_ip_host_entry ${AGENT_EXTRA_WORKERS_IPS[i]} ${AGENT_EXTRA_WORKERS_HOSTNAMES[i]}
      elif [[ "$IP_STACK" = "v6" ]]; then
          AGENT_EXTRA_WORKERS_IPSV6+=($(nth_ip ${EXTERNAL_SUBNET_V6} ${ip}))
          add_dns_entry ${AGENT_EXTRA_WORKERS_IPSV6[i]} ${AGENT_EXTRA_WORKERS_HOSTNAMES[i]}
          add_ip_host_entry ${AGENT_EXTRA_WORKERS_IPSV6[i]} ${AGENT_EXTRA_WORKERS_HOSTNAMES[i]}
      else
          # v4v6
          AGENT_EXTRA_WORKERS_IPS+=($(nth_ip ${EXTERNAL_SUBNET_V4} ${ip}))
          AGENT_EXTRA_WORKERS_IPSV6+=($(nth_ip $EXTERNAL_SUBNET_V6 ${ip}))
          add_dns_entry ${AGENT_EXTRA_WORKERS_IPS[i]} ${AGENT_EXTRA_WORKERS_HOSTNAMES[i]}
          add_ip_host_entry ${AGENT_EXTRA_WORKERS_IPS[i]} ${AGENT_EXTRA_WORKERS_HOSTNAMES[i]}
          add_dns_entry ${AGENT_EXTRA_WORKERS_IPSV6[i]} ${AGENT_EXTRA_WORKERS_HOSTNAMES[i]}
      fi

      # Get the generated mac addresses
      AGENT_EXTRA_WORKERS_MACS+=($(sudo virsh dumpxml $cluster_name | xmllint --xpath "string(//interface[descendant::source[@bridge = '${BAREMETAL_NETWORK_NAME}']]/mac/@address)" -))
      if [[ ! -z "${BOND_PRIMARY_INTERFACE:-}" ]]; then
        # For a bond, a random mac is added for the 2nd interface
        AGENT_EXTRA_WORKERS_MACS+=($(sudo virsh domiflist ${cluster_name} | grep ${BAREMETAL_NETWORK_NAME} | grep -v ${AGENT_NODES_MACS[-1]} | awk '{print $5}'))
      fi
    done
}

# External load balancer configuration.
# The following ports are opened in firewalld so that libvirt VMs can communicate with haproxy.
export MACHINE_CONFIG_SERVER_PORT=22623
export KUBE_API_PORT=6443
export INGRESS_ROUTER_PORT=443
export AGENT_NODE0_IPSV6=${AGENT_NODE0_IPSV6:-}

export AGENT_EXTRAWORKER_NODE_TO_ADD=${AGENT_EXTRAWORKER_NODE_TO_ADD:-"0"}