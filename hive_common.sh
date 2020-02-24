#!/bin/bash

export HIVE1_BAREMETAL_NETWORK_NAME=${HIVE1_BAREMETAL_NETWORK_NAME:-hive1bm}
export HIVE1_CLUSTER_DOMAIN="${HIVE1_CLUSTER_NAME}.${BASE_DOMAIN}"
export HIVE1_CLUSTER_NAME=${HIVE1_CLUSTER_NAME:-hive1}
export HIVE1_CLUSTER_SUBNET=${HIVE1_CLUSTER_SUBNET:-"10.128.1.0/14"}
export HIVE1_DNS_VIP=${HIVE1_DNS_VIP:-"192.168.112.2"}
export HIVE1_EXTERNAL_SUBNET=${HIVE1_EXTERNAL_SUBNET:-"192.168.112.0/24"}
export HIVE1_MIRROR_IP=${HIVE1_MIRROR_IP:-$HIVE1_PROVISIONING_HOST_IP}
export HIVE1_NODES_FILE=${HIVE1_NODES_FILE:-"${WORKING_DIR}/hive1_ironic_nodes.json"}
export HIVE1_NUM_MASTERS=${HIVE1_NUM_MASTERS:-$NUM_MASTERS}
export HIVE1_NUM_WORKERS=${HIVE1_NUM_WORKERS:-$NUM_WORKERS}
export HIVE1_PROVISIONING_HOST_EXTERNAL_IP=${HIVE1_PROVISIONING_HOST_EXTERNAL_IP:-$(python -c "import ipaddress; print(next(ipaddress.ip_network(u\"$HIVE1_EXTERNAL_SUBNET\").hosts()))")}
export HIVE1_PROVISIONING_HOST_IP=${HIVE1_PROVISIONING_HOST_IP:-$(python -c "import ipaddress; print(next(ipaddress.ip_network(u\"$HIVE1_PROVISIONING_NETWORK\").hosts()))")}
export HIVE1_PROVISIONING_NETMASK=${HIVE1_PROVISIONING_NETMASK:-$(ipcalc --netmask $HIVE1_PROVISIONING_NETWORK | cut -d= -f2)}
export HIVE1_PROVISIONING_NETWORK=${HIVE1_PROVISIONING_NETWORK:-172.22.1.0/24}
export HIVE1_PROVISIONING_NETWORK_NAME=${HIVE1_PROVISIONING_NETWORK_NAME:-hive1prov}
export HIVE1_SERVICE_SUBNET=${HIVE1_SERVICE_SUBNET:-"172.30.1.0/16"}

export HIVE2_BAREMETAL_NETWORK_NAME=${HIVE2_BAREMETAL_NETWORK_NAME:-hive2bm}
export HIVE2_CLUSTER_DOMAIN="${HIVE2_CLUSTER_NAME}.${BASE_DOMAIN}"
export HIVE2_CLUSTER_NAME=${HIVE2_CLUSTER_NAME:-hive2}
export HIVE2_CLUSTER_SUBNET=${HIVE2_CLUSTER_SUBNET:-"10.128.2.0/14"}
export HIVE2_DNS_VIP=${HIVE2_DNS_VIP:-"192.168.113.2"}
export HIVE2_EXTERNAL_SUBNET=${HIVE2_EXTERNAL_SUBNET:-"192.168.113.0/24"}
export HIVE2_MIRROR_IP=${HIVE2_MIRROR_IP:-$HIVE2_PROVISIONING_HOST_IP}
export HIVE2_NODES_FILE=${HIVE2_NODES_FILE:-"${WORKING_DIR}/hive2_ironic_nodes.json"}
export HIVE2_NUM_MASTERS=${HIVE2_NUM_MASTERS:-$NUM_MASTERS}
export HIVE2_NUM_WORKERS=${HIVE2_NUM_WORKERS:-$NUM_WORKERS}
export HIVE2_PROVISIONING_HOST_EXTERNAL_IP=${HIVE2_PROVISIONING_HOST_EXTERNAL_IP:-$(python -c "import ipaddress; print(next(ipaddress.ip_network(u\"$HIVE2_EXTERNAL_SUBNET\").hosts()))")}
export HIVE2_PROVISIONING_HOST_IP=${HIVE2_PROVISIONING_HOST_IP:-$(python -c "import ipaddress; print(next(ipaddress.ip_network(u\"$HIVE2_PROVISIONING_NETWORK\").hosts()))")}
export HIVE2_PROVISIONING_NETMASK=${HIVE2_PROVISIONING_NETMASK:-$(ipcalc --netmask $HIVE2_PROVISIONING_NETWORK | cut -d= -f2)}
export HIVE2_PROVISIONING_NETWORK=${HIVE2_PROVISIONING_NETWORK:-172.22.2.0/24}
export HIVE2_PROVISIONING_NETWORK_NAME=${HIVE2_PROVISIONING_NETWORK_NAME:-hive2prov}
export HIVE2_SERVICE_SUBNET=${HIVE2_SERVICE_SUBNET:-"172.30.2.0/16"}

# Utility to make it easier to override some of the variables from
# common.sh. The first set before the blank line must be exported for
# the setup-playbook to work because metal3-dev-env reads the
# variables directly instead of making it possible to pass the values
# on the command line. The rest are used by scripts in this repo and
# it's easier to just change their value than to update all of the
# relevant functions to take them as a parameter.

HIVE_OVERRIDE_VARS="
EXTERNAL_SUBNET
CLUSTER_NAME
CLUSTER_DOMAIN

NODES_FILE
PROVISIONING_NETWORK
PROVISIONING_NETWORK_NAME
BAREMETAL_NETWORK_NAME
MIRROR_IP
DNS_VIP
PROVISIONING_HOST_IP
"

function override_vars_for_hive() {
    local num=$1
    local base_varname
    local hive_varname

    for base_varname in $HIVE_OVERRIDE_VARS; do
        hive_varname="HIVE${num}_${base_varname}"
        if [ -z "${!hive_varname}" ]; then
            echo "${hive_varname} is not set"
            exit 1
        fi
        export ${base_varname}=${!hive_varname}
    done
}
