#!/usr/bin/env bash
set -euxo pipefail

lldp_dir="$(dirname "$(readlink -f "$0")")"
# shellcheck disable=SC1091
source "${lldp_dir}/../common.sh"

# Emulate a production top-of-rack LLDP switch for the cluster VMs.
#
# The libvirt bridges do not forward the link-local scoped LLDP group
# address (01:80:C2:00:00:0E) between ports, and NetworkManager >= 1.59.1
# filters LLDP frames sourced by the local interface, so cluster nodes
# never see any LLDP neighbor. Run lldpd on the hypervisor bound to the
# libvirt tap devices (vnet*): a frame transmitted on a tap is delivered
# straight to the VM NIC (no bridge forwarding involved), so each node
# receives LLDPDUs inbound exactly like from a real switch port.
#
# lldpd tracks interface add/remove via netlink, so taps created when the
# VMs boot later (or recreated on node reboot) are picked up automatically.

sudo dnf -y install lldpd

# tx-interval 5: fast neighbor appearance for tests.
# interface pattern vnet*: only libvirt taps, never physical host NICs.
sudo tee /etc/lldpd.d/lldp-tor.conf <<EOF
configure lldp tx-interval 5
configure system hostname ${LLDP_TOR_SYSTEM_NAME}
configure system interface pattern vnet*
EOF

sudo systemctl enable --now lldpd
# Re-apply the configuration if lldpd was already running
sudo systemctl restart lldpd

echo "LLDP ToR switch emulation running: system name ${LLDP_TOR_SYSTEM_NAME}, interfaces vnet*"
