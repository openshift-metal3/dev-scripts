#!/bin/bash
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../../" && pwd )"
source $SCRIPTDIR/common.sh

NODE_INDEX=${1:-0}
STATIC_IP=${2:-"192.168.111.90/24"}
CONNECTION_NAME="copy-network-static"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q"

# Derive the DNS hostname from MASTER_HOSTNAME_FORMAT (e.g. "master-0")
node_hostname=$(printf ${MASTER_HOSTNAME_FORMAT} ${NODE_INDEX})

# Get the node's current DHCP IP (assigned by virsh) to SSH into the live environment
node_ip=$(sudo virsh net-dumpxml ${BAREMETAL_NETWORK_NAME} | xmllint --xpath \
    "string(//dns[*]/host/hostname[. = '${node_hostname}']/../@ip)" -)

if [ -z "$node_ip" ]; then
    echo "ERROR: Could not resolve IP for ${node_hostname} on network ${BAREMETAL_NETWORK_NAME}"
    exit 1
fi

echo "Waiting for live environment SSH on ${node_hostname} (${node_ip})..."
until ssh $SSH_OPTS core@${node_ip} true 2>/dev/null; do
    sleep 10
done

echo "SSH available on ${node_hostname}, injecting static network keyfile"

# Determine the MAC address of the interface that has the current DHCP IP,
# and the default gateway and DNS from the live environment.
iface_mac=$(ssh $SSH_OPTS core@${node_ip} \
    "ip -j addr show | jq -r '.[] | select(.addr_info[]? | .local == \"${node_ip}\") | .address'")
gateway=$(ssh $SSH_OPTS core@${node_ip} \
    "ip route show default | awk '/default/ {print \$3; exit}'")
dns=$(ssh $SSH_OPTS core@${node_ip} \
    "awk '/^nameserver/ {print \$2; exit}' /etc/resolv.conf")

echo "Interface MAC: ${iface_mac}, Gateway: ${gateway}, DNS: ${dns}, Static IP: ${STATIC_IP}"

if [ -z "$iface_mac" ] || [ -z "$gateway" ]; then
    echo "ERROR: Could not determine interface MAC or gateway on ${node_hostname}"
    exit 1
fi

# Write a static NetworkManager keyfile using a static IP distinct from the DHCP
# address, so the installed OS can be verified to be using the static config.
# Bound to the primary interface by MAC address and uses autoconnect-priority=1
# to take precedence over auto-generated DHCP connections (priority -100).
ssh $SSH_OPTS core@${node_ip} \
    "sudo bash -c 'umask 177; cat > /etc/NetworkManager/system-connections/${CONNECTION_NAME}.nmconnection'" << EOF
[connection]
id=${CONNECTION_NAME}
type=ethernet
autoconnect=true
autoconnect-priority=1

[ethernet]
mac-address=${iface_mac}

[ipv4]
address1=${STATIC_IP},${gateway}
dns=${dns};
method=manual

[ipv6]
method=disabled

[proxy]
EOF

echo "Injected static keyfile '${CONNECTION_NAME}.nmconnection' on ${node_hostname}"
echo "  Static IP: ${STATIC_IP}, Gateway: ${gateway}, DNS: ${dns}"
