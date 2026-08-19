#!/bin/bash
# NAT64/DNS64 helper functions for enabling IPv6-only clusters
# on IPv4-only hosts using TAYGA (NAT64) and unbound (DNS64).

export NAT64_TAYGA_CONF="/etc/tayga.conf"
export NAT64_TAYGA_DATA_DIR="/var/db/tayga"
export NAT64_TUN_INTERFACE="nat64"
export NAT64_DNS64_PORT="5353"
export NAT64_UNBOUND_CONF="/etc/unbound/unbound-dns64.conf"
export NAT64_UNBOUND_SERVICE="unbound-dns64"
export NAT64_DNSMASQ_CONF="/etc/NetworkManager/dnsmasq.d/nat64-dns64.conf"

function configure_nat64_bridge_ipv6() {
    local bridge_name="${BAREMETAL_NETWORK_NAME}"
    local ipv6_addr
    ipv6_addr=$(nth_ip "$EXTERNAL_SUBNET_V6" 1)

    echo "Configuring IPv6 on bridge ${bridge_name} for NAT64..."

    # Enable IPv6 forwarding
    sudo sysctl -w net.ipv6.conf.all.forwarding=1
    sudo sysctl -w net.ipv6.conf.default.forwarding=1

    # Add IPv6 address to the baremetal bridge
    local prefix_len
    prefix_len=$(echo "${EXTERNAL_SUBNET_V6}" | cut -d'/' -f2)
    sudo ip -6 addr add "${ipv6_addr}/${prefix_len}" dev "${bridge_name}" 2>/dev/null || true

    echo "IPv6 address ${ipv6_addr}/${prefix_len} configured on ${bridge_name}"
}

function configure_tayga() {
    echo "Configuring TAYGA NAT64 daemon..."

    # Create TAYGA data directory
    sudo mkdir -p "${NAT64_TAYGA_DATA_DIR}"

    # Write TAYGA configuration
    sudo tee "${NAT64_TAYGA_CONF}" > /dev/null <<EOF
tun-device ${NAT64_TUN_INTERFACE}
ipv4-addr ${NAT64_V4_ADDR}
ipv6-addr ${NAT64_V6_ADDR}
prefix ${NAT64_PREFIX}
dynamic-pool ${NAT64_V4_POOL}
data-dir ${NAT64_TAYGA_DATA_DIR}
EOF

    # Create the TUN device via TAYGA
    sudo tayga --mktun

    # Configure the TUN interface
    sudo ip link set "${NAT64_TUN_INTERFACE}" up

    # Add IPv4 route for the NAT64 pool via the TUN interface
    sudo ip route add "${NAT64_V4_POOL}" dev "${NAT64_TUN_INTERFACE}" 2>/dev/null || true

    # Add IPv6 route for the NAT64 prefix via the TUN interface
    sudo ip -6 route add "${NAT64_PREFIX}" dev "${NAT64_TUN_INTERFACE}" 2>/dev/null || true

    # Enable IPv4 forwarding
    sudo sysctl -w net.ipv4.ip_forward=1

    # Set up iptables MASQUERADE for translated traffic
    sudo iptables -t nat -C POSTROUTING -s "${NAT64_V4_POOL}" -j MASQUERADE 2>/dev/null || \
        sudo iptables -t nat -A POSTROUTING -s "${NAT64_V4_POOL}" -j MASQUERADE

    # Start TAYGA daemon
    sudo tayga

    echo "TAYGA NAT64 daemon started (prefix=${NAT64_PREFIX}, pool=${NAT64_V4_POOL})"
}

function configure_dns64() {
    echo "Configuring unbound for DNS64..."

    # Remove any legacy CoreDNS DNS64 service from before the switch to unbound so
    # it does not hold the DNS64 port.
    _nat64_remove_legacy_coredns

    # Discover the host's real upstream resolvers. NAT64 hosts frequently cannot
    # reach public resolvers (e.g. 8.8.8.8) through their firewall, so forward
    # DNS64 queries to whatever resolvers the host itself uses. When NetworkManager
    # runs in dnsmasq mode /etc/resolv.conf points at a loopback stub and the real
    # upstream servers live in no-stub-resolv.conf.
    local upstreams
    upstreams=$(awk '/^nameserver/ && $2 != "127.0.0.1" && $2 != "::1" {print $2}' /run/NetworkManager/no-stub-resolv.conf 2>/dev/null)
    if [[ -z "${upstreams//[[:space:]]/}" ]]; then
        upstreams=$(awk '/^nameserver/ && $2 != "127.0.0.1" && $2 != "::1" {print $2}' /etc/resolv.conf 2>/dev/null)
    fi
    upstreams=${upstreams:-8.8.8.8}
    echo "DNS64 upstream resolvers: ${upstreams}"

    # Write the unbound DNS64 config. dns64-synthall makes unbound synthesize an
    # AAAA in ${NAT64_PREFIX} for EVERY name, even ones that already have a native
    # AAAA: the host has no native IPv6 egress, so all IPv6 must be routed through
    # NAT64/TAYGA. (The CoreDNS dns64 plugin was used previously but its build did
    # not synthesize at all, so IPv6-only nodes received unreachable native AAAA.)
    sudo mkdir -p "$(dirname "${NAT64_UNBOUND_CONF}")"
    sudo tee "${NAT64_UNBOUND_CONF}" > /dev/null <<EOF
server:
    verbosity: 1
    interface: 127.0.0.1@${NAT64_DNS64_PORT}
    port: ${NAT64_DNS64_PORT}
    do-ip4: yes
    do-ip6: yes
    do-udp: yes
    do-tcp: yes
    access-control: 127.0.0.0/8 allow
    access-control: ::1 allow
    module-config: "dns64 iterator"
    dns64-prefix: ${NAT64_PREFIX}
    dns64-synthall: yes
forward-zone:
    name: "."
$(for ns in ${upstreams}; do echo "        forward-addr: ${ns}"; done)
EOF

    # Create systemd service for the DNS64 unbound instance
    sudo tee "/etc/systemd/system/${NAT64_UNBOUND_SERVICE}.service" > /dev/null <<EOF
[Unit]
Description=unbound DNS64 resolver for NAT64
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/unbound -d -p -c ${NAT64_UNBOUND_CONF}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now "${NAT64_UNBOUND_SERVICE}.service"

    # Configure the host's NetworkManager dnsmasq to forward to the DNS64 resolver
    sudo tee "${NAT64_DNSMASQ_CONF}" > /dev/null <<EOF
# Forward DNS queries to the unbound DNS64 resolver for NAT64 translation
server=127.0.0.1#${NAT64_DNS64_PORT}
EOF

    sudo systemctl reload NetworkManager

    # Point every cluster-facing libvirt network's dnsmasq at the DNS64 resolver.
    # This includes the baremetal network AND any extra networks: without it the
    # extra networks' dnsmasq reads /etc/resolv.conf and returns native AAAA
    # records (e.g. quay.io's 2600:1f18::*) that are unreachable from the isolated
    # IPv6-only cluster, so nodes fail to pull images during firstboot.
    local net
    for net in "${BAREMETAL_NETWORK_NAME}" ${EXTRA_NETWORK_NAMES:-}; do
        _nat64_point_libvirt_dns64 "${net}"
    done

    echo "unbound DNS64 configured on port ${NAT64_DNS64_PORT}"
}

# Rewrite a libvirt network's dnsmasq so it forwards exclusively to the DNS64
# resolver, then recreate the bridge carrier/addr_gen so its IPv6 (and thus DNS)
# is up before the VMs boot. Safe to call for a network that does not exist.
function _nat64_point_libvirt_dns64() {
    local net="$1"
    local xml="${WORKING_DIR}/${net}-dns64.xml"

    sudo virsh net-info "${net}" >/dev/null 2>&1 || return 0

    echo "Pointing libvirt network ${net} dnsmasq at DNS64 resolver..."
    sudo virsh net-dumpxml "${net}" > "${xml}"

    # Idempotent: only inject the forwarding options if not already present.
    if ! grep -q "server=127.0.0.1#${NAT64_DNS64_PORT}" "${xml}"; then
        sudo sed -i "/<\/dnsmasq:options>/i\\
    <dnsmasq:option value='server=127.0.0.1#${NAT64_DNS64_PORT}'/>\\
    <dnsmasq:option value='no-resolv'/>" "${xml}"
    fi

    sudo virsh net-destroy "${net}"
    sudo virsh net-undefine "${net}"
    sudo virsh net-define "${xml}"
    sudo virsh net-start "${net}"

    # net-destroy drops the bridge; restore a dummy for carrier and addr_gen_mode=0
    # so the network's IPv6 address comes up before the VMs provide carrier (needed
    # for IPv6 on EL9).
    sudo ip link add name "${net}-dmy" up master "${net}" type dummy 2>/dev/null || true
    echo 0 | sudo dd of="/proc/sys/net/ipv6/conf/${net}/addr_gen_mode" 2>/dev/null || true
}

# When running an IPv6-only cluster via NAT64, the in-cluster Ironic runs as
# IPv6-only pods (hostNetwork on v6-only nodes) and cannot reach the sushy/redfish
# BMC emulator at its IPv4 baremetal address. Rewrite the generated node BMC
# addresses to the host's IPv6 baremetal address (which sushy also listens on) so
# both the bootstrap Ironic and the pivoted in-cluster Ironic can control the nodes.
function nat64_fixup_bmc_addresses() {
    local v4host v6host
    v4host=$(nth_ip "${EXTERNAL_SUBNET_V4}" 1)
    v6host=$(nth_ip "${EXTERNAL_SUBNET_V6}" 1)
    if [[ -z "${v4host}" || -z "${v6host}" ]]; then
        echo "nat64_fixup_bmc_addresses: missing v4/v6 baremetal host address, skipping"
        return 0
    fi
    echo "Rewriting node BMC addresses from ${v4host} to [${v6host}] for NAT64..."
    local f tmp
    for f in "${NODES_FILE}" "${NODES_FILE}.orig" "${EXTRA_NODES_FILE:-}" "${ARM_NODES_FILE:-}"; do
        [[ -n "${f}" && -f "${f}" ]] || continue
        tmp="${f}.nat64"
        # Literal (non-regex) host replacement via split/join on the "//host:" token.
        jq --arg old "//${v4host}:" --arg new "//[${v6host}]:" \
            '(.nodes[]?.driver_info.address) |= (. / $old | join($new))' \
            "${f}" > "${tmp}" && mv "${tmp}" "${f}"
    done
}

# Regenerate the sushy-tools BMC emulator TLS certificate so it is valid for the
# host's IPv6 baremetal address in addition to its IPv4 one. metal3-dev-env only
# puts the IPv4 baremetal address in the cert's SAN, but for NAT64 the in-cluster
# Ironic pods are IPv6-only and must reach the BMC over IPv6; without the IPv6 SAN
# they reject the redfish connection with an "IP address mismatch" TLS error.
# (On OCP >= 4.22 dev-scripts no longer emits disableCertificateVerification, so
# certificate verification is always on and the cert MUST carry the IPv6 SAN.)
#
# This must run before 05_create_install_config.sh, which embeds this cert into the
# install-config trust bundle (see ocp_install_env.sh). The existing key is reused
# and the sushy-tools container is restarted so it serves the new cert. Idempotent
# and a no-op when sushy or the IPv6 address is not present.
function nat64_fixup_sushy_cert() {
    local sushy_dir="${WORKING_DIR}/virtualbmc/sushy-tools"
    local cert="${sushy_dir}/cert.pem"
    local key="${sushy_dir}/key.pem"
    local v4host v6host
    v4host=$(nth_ip "${EXTERNAL_SUBNET_V4}" 1)
    v6host=$(nth_ip "${EXTERNAL_SUBNET_V6}" 1)
    if [[ ! -f "${cert}" || ! -f "${key}" || -z "${v6host}" ]]; then
        echo "nat64_fixup_sushy_cert: sushy cert/key or IPv6 host address missing, skipping"
        return 0
    fi

    # Already valid for the IPv6 address? Nothing to do.
    if sudo openssl x509 -in "${cert}" -noout -text 2>/dev/null | grep -qiF "${v6host}"; then
        echo "sushy BMC cert already valid for ${v6host}"
        return 0
    fi

    echo "Regenerating sushy BMC cert with SANs IP:${v4host}, IP:${v6host} for NAT64..."
    local tmp
    tmp=$(mktemp -d)
    cat > "${tmp}/san.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = metal3.io
[SAN]
subjectAltName = IP:${v4host},IP:${v6host}
basicConstraints = CA:TRUE,pathlen:0
EOF
    sudo openssl req -x509 -key "${key}" -out "${tmp}/cert.pem" -days 3650 \
        -subj "/CN=metal3.io" -config "${tmp}/san.cnf" -extensions SAN
    sudo cp "${tmp}/cert.pem" "${cert}"
    rm -rf "${tmp}"

    # Restart sushy so it serves the regenerated certificate.
    sudo podman restart sushy-tools 2>/dev/null || true

    echo "sushy BMC cert regenerated for ${v4host} and ${v6host}"
}

# Remove the legacy CoreDNS DNS64 service (superseded by unbound). No-op if absent.
function _nat64_remove_legacy_coredns() {
    if sudo systemctl is-active --quiet coredns-nat64.service 2>/dev/null; then
        sudo systemctl stop coredns-nat64.service
    fi
    sudo systemctl disable coredns-nat64.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/coredns-nat64.service
    sudo rm -rf /etc/coredns
    sudo systemctl daemon-reload
}

function cleanup_nat64() {
    echo "Cleaning up NAT64/DNS64 configuration..."

    # Remove any legacy CoreDNS DNS64 service from before the switch to unbound
    _nat64_remove_legacy_coredns

    # Stop and disable the DNS64 unbound instance
    if sudo systemctl is-active --quiet "${NAT64_UNBOUND_SERVICE}.service" 2>/dev/null; then
        sudo systemctl stop "${NAT64_UNBOUND_SERVICE}.service"
    fi
    sudo systemctl disable "${NAT64_UNBOUND_SERVICE}.service" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/${NAT64_UNBOUND_SERVICE}.service"
    sudo systemctl daemon-reload

    # Remove unbound DNS64 configuration
    sudo rm -f "${NAT64_UNBOUND_CONF}"

    # Remove the per-network DNS64 dummy carrier interfaces
    local net
    for net in "${BAREMETAL_NETWORK_NAME}" ${EXTRA_NETWORK_NAMES:-}; do
        sudo ip link del "${net}-dmy" 2>/dev/null || true
    done
    # Remove the legacy baremetal dummy name used by earlier revisions
    sudo ip link del bm-ipv6-dummy 2>/dev/null || true

    # Remove dnsmasq DNS64 forwarding config
    sudo rm -f "${NAT64_DNSMASQ_CONF}"
    if systemctl is-active --quiet NetworkManager; then
        sudo systemctl reload NetworkManager
    fi

    # Stop TAYGA
    sudo tayga --rmtun 2>/dev/null || true
    sudo pkill -f "^tayga" 2>/dev/null || true

    # Remove NAT64 routes
    sudo ip route del "${NAT64_V4_POOL}" dev "${NAT64_TUN_INTERFACE}" 2>/dev/null || true
    sudo ip -6 route del "${NAT64_PREFIX}" dev "${NAT64_TUN_INTERFACE}" 2>/dev/null || true

    # Remove iptables masquerade rule
    sudo iptables -t nat -D POSTROUTING -s "${NAT64_V4_POOL}" -j MASQUERADE 2>/dev/null || true

    # Clean up TAYGA data and config
    sudo rm -rf "${NAT64_TAYGA_DATA_DIR}"
    sudo rm -f "${NAT64_TAYGA_CONF}"

    echo "NAT64/DNS64 cleanup complete"
}
