#!/bin/bash
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../../" && pwd )"
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/agent/common.sh
source $SCRIPTDIR/network.sh

CONNECTION_NAME="copy-network-static"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q"

# master-0 keeps its DHCP IP as the static IP (to preserve etcd membership),
# so we reach it via its virsh-assigned IP.
# master-1 uses a distinct static IP outside the DHCP range, so we SSH to that
# IP directly to prove the installed OS is using the static config.
subnet_prefix=$(echo "${EXTERNAL_SUBNET_V4}" | cut -d'/' -f2)
master0_hostname=$(printf ${MASTER_HOSTNAME_FORMAT} 0)
master0_ip=$(sudo virsh net-dumpxml ${BAREMETAL_NETWORK_NAME} | xmllint --xpath \
    "string(//dns[*]/host/hostname[. = '${master0_hostname}']/../@ip)" -)
master1_ip=""
for offset in $(seq 90 254); do
    candidate=$(nth_ip ${EXTERNAL_SUBNET_V4} ${offset})
    if ! sudo virsh net-dumpxml ${BAREMETAL_NETWORK_NAME} | xmllint --xpath "//dns[*]/host[@ip = '${candidate}']" - &>/dev/null; then
        master1_ip=${candidate}
        break
    fi
done
if [ -z "${master1_ip}" ]; then
    echo "ERROR: could not find the static IP for master-1 in ${EXTERNAL_SUBNET_V4}"
    exit 1
fi

declare -A NODE_IPS=([0]="${master0_ip}" [1]="${master1_ip}")

failed=0
for node_index in 0 1; do
    node_hostname=$(printf ${MASTER_HOSTNAME_FORMAT} ${node_index})
    node_ip=${NODE_IPS[$node_index]}

    echo "Checking ${node_hostname} at ${node_ip} for connection '${CONNECTION_NAME}'..."

    if ! ssh $SSH_OPTS core@${node_ip} true 2>/dev/null; then
        echo "FAIL: Cannot SSH to ${node_hostname} at ${node_ip}"
        failed=1
        continue
    fi

    # Verify the NetworkManager keyfile exists in the installed OS
    if ! ssh $SSH_OPTS core@${node_ip} \
        "sudo ls /etc/NetworkManager/system-connections/ | grep -q '${CONNECTION_NAME}'"; then
        echo "FAIL: Connection keyfile '${CONNECTION_NAME}' not found on ${node_hostname}"
        failed=1
        continue
    fi

    # Verify nmcli reports the connection with static method - this is the proof
    # that --copy-network copied the user-created keyfile to the installed OS
    if ! ssh $SSH_OPTS core@${node_ip} \
        "sudo nmcli -f ipv4.method connection show '${CONNECTION_NAME}' | grep -q 'manual'"; then
        echo "FAIL: Connection '${CONNECTION_NAME}' does not have static IPv4 method on ${node_hostname}"
        failed=1
        continue
    fi

    echo "PASS: ${node_hostname} has connection '${CONNECTION_NAME}' with method=manual"
done

if [ $failed -ne 0 ]; then
    echo "FAIL: Network config persistence validation failed on one or more nodes"
    exit 1
fi

echo "PASS: Static network config persisted after installation on all nodes"
