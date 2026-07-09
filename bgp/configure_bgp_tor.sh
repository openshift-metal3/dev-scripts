#!/usr/bin/env bash
set -euxo pipefail

bgp_dir="$(dirname "$(readlink -f "$0")")"
# shellcheck disable=SC1091
source "${bgp_dir}/../common.sh"
# shellcheck disable=SC1091
source "${bgp_dir}/../network.sh"

# Deploys an FRR container on the host network acting as a top-of-rack BGP
# speaker for the baremetal network. Cluster nodes (e.g. BGP-based VIP
# management, enhancement openshift/enhancements#1982) peer with it via
# dynamic neighbors; learned routes are installed into the host kernel by
# zebra, so the hypervisor reaches advertised VIPs over the BGP paths.

BGP_TOR_NAME="bgp-tor"
BGP_TOR_DIR="${WORKING_DIR}/bgp-tor"

mkdir -p "${BGP_TOR_DIR}"

if [[ -n "${EXTERNAL_SUBNET_V4:-}" ]]; then
    ROUTER_ID="$(nth_ip "${EXTERNAL_SUBNET_V4}" 1)"
else
    # BGP router IDs are always in IPv4 dotted-quad format; use a fixed
    # documentation-range ID for IPv6-only deployments.
    ROUTER_ID="192.0.2.1"
fi

# Accept dynamic BGP sessions from anywhere on the external subnet(s) and
# only activate the address families a peer could exist on.
LISTEN_RANGES=""
ADDRESS_FAMILIES=""
if [[ -n "${EXTERNAL_SUBNET_V4:-}" ]]; then
    LISTEN_RANGES+=" bgp listen range ${EXTERNAL_SUBNET_V4} peer-group CLUSTER
"
    ADDRESS_FAMILIES+=" !
 address-family ipv4 unicast
  neighbor CLUSTER activate
 exit-address-family
"
fi
if [[ -n "${EXTERNAL_SUBNET_V6:-}" ]]; then
    LISTEN_RANGES+=" bgp listen range ${EXTERNAL_SUBNET_V6} peer-group CLUSTER
"
    ADDRESS_FAMILIES+=" !
 address-family ipv6 unicast
  neighbor CLUSTER activate
 exit-address-family
"
fi

# "no bgp ebgp-requires-policy" relaxes RFC 8212; without it FRR 8+ refuses
# to exchange routes with eBGP peers unless explicit policies are configured.
cat > "${BGP_TOR_DIR}/frr.conf" <<EOF
frr defaults traditional
hostname ${BGP_TOR_NAME}
log stdout informational
!
router bgp ${BGP_TOR_ASN}
 bgp router-id ${ROUTER_ID}
 bgp log-neighbor-changes
 no bgp ebgp-requires-policy
 neighbor CLUSTER peer-group
 neighbor CLUSTER remote-as ${BGP_CLUSTER_ASN}
${LISTEN_RANGES}${ADDRESS_FAMILIES}!
EOF

cat > "${BGP_TOR_DIR}/daemons" <<EOF
zebra=yes
bgpd=yes
ospfd=no
ospf6d=no
ripd=no
ripngd=no
isisd=no
pimd=no
ldpd=no
nhrpd=no
eigrpd=no
babeld=no
sharpd=no
pbrd=no
bfdd=no
fabricd=no
vrrpd=no
pathd=no

vtysh_enable=yes
zebra_options="  -A 127.0.0.1 -s 90000000"
bgpd_options="   -A 127.0.0.1"
EOF

sudo firewall-cmd --zone=libvirt --permanent --add-port=179/tcp
sudo firewall-cmd --zone=libvirt --add-port=179/tcp

sudo podman run -d --replace --name "${BGP_TOR_NAME}" --net host --privileged \
    -v "${BGP_TOR_DIR}/frr.conf:/etc/frr/frr.conf:z" \
    -v "${BGP_TOR_DIR}/daemons:/etc/frr/daemons:z" \
    "${BGP_TOR_IMAGE}"

echo "BGP ToR speaker running: AS ${BGP_TOR_ASN}, router-id ${ROUTER_ID}, listening on port 179"
