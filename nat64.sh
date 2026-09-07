#!/bin/bash
# NAT64/DNS64 helper functions for enabling IPv6-only clusters
# on IPv4-only hosts using TAYGA (NAT64) and unbound (DNS64).

export NAT64_TAYGA_CONF="/etc/tayga.conf"
export NAT64_TAYGA_DATA_DIR="/var/db/tayga"
export NAT64_TAYGA_SERVICE="nat64-tayga"
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

    # Run TAYGA as a systemd service so the translator, its TUN device, routes and
    # forwarding survive a host reboot (mirroring the unbound DNS64 service). All
    # setup lives in ExecStartPre so it is re-established on every (re)start; the
    # '-' prefix and the -C||-A guard keep it idempotent (re-running 02_configure_host
    # no longer fails on an already-existing TUN device).
    sudo tee "/etc/systemd/system/${NAT64_TAYGA_SERVICE}.service" > /dev/null <<EOF
[Unit]
Description=TAYGA NAT64 translator
After=network.target

[Service]
Type=simple
ExecStartPre=-/usr/sbin/tayga --mktun
ExecStartPre=/usr/sbin/ip link set ${NAT64_TUN_INTERFACE} up
ExecStartPre=-/usr/sbin/ip route add ${NAT64_V4_POOL} dev ${NAT64_TUN_INTERFACE}
ExecStartPre=-/usr/sbin/ip -6 route add ${NAT64_PREFIX} dev ${NAT64_TUN_INTERFACE}
ExecStartPre=/usr/sbin/sysctl -w net.ipv4.ip_forward=1
ExecStartPre=/bin/bash -c '/usr/sbin/iptables -t nat -C POSTROUTING -s ${NAT64_V4_POOL} -j MASQUERADE 2>/dev/null || /usr/sbin/iptables -t nat -A POSTROUTING -s ${NAT64_V4_POOL} -j MASQUERADE'
ExecStart=/usr/sbin/tayga --nodetach -c ${NAT64_TAYGA_CONF}
# Put the freshly (re)created TUN into firewalld's trusted zone. Traffic to an ipmi
# BMC (BMC_DRIVER=mixed/ipmi) is translated by TAYGA and re-enters the host locally
# on this interface destined for the vbmc port on the baremetal address; without a
# permissive zone firewalld drops it (the vbmc ports are only opened in the libvirt
# zone, and an unassigned interface falls into the default 'public' zone), so the
# in-cluster/bootstrap Ironic cannot reach ipmi BMCs. The '-' prefix keeps this a
# no-op when firewalld is not running, and re-runs on every (re)start since the TUN
# is recreated each time.
ExecStartPost=-/usr/bin/firewall-cmd --zone=trusted --change-interface=${NAT64_TUN_INTERFACE}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "${NAT64_TAYGA_SERVICE}.service"
    # restart (not just start) so a re-run picks up any config/unit changes.
    sudo systemctl restart "${NAT64_TAYGA_SERVICE}.service"

    # Persist the trusted-zone binding so it survives a firewalld reload/reboot too
    # (the ExecStartPost above only sets the runtime binding on each tayga start).
    # Guarded: harmless no-op when firewalld is absent.
    if command -v firewall-cmd >/dev/null 2>&1 && sudo firewall-cmd --state >/dev/null 2>&1; then
        sudo firewall-cmd --permanent --zone=trusted --change-interface="${NAT64_TUN_INTERFACE}" 2>/dev/null || true
        sudo firewall-cmd --zone=trusted --change-interface="${NAT64_TUN_INTERFACE}" 2>/dev/null || true
    fi

    echo "TAYGA NAT64 daemon started (prefix=${NAT64_PREFIX}, pool=${NAT64_V4_POOL})"
}

function configure_dns64() {
    echo "Configuring unbound for DNS64..."

    # Remove any legacy CoreDNS DNS64 service from before the switch to unbound so
    # it does not hold the DNS64 port.
    _nat64_remove_legacy_coredns

    # Determine the upstream resolvers DNS64 forwards to. An explicit
    # NAT64_DNS64_UPSTREAM (space-separated) always wins. Otherwise discover the
    # host's real resolvers: NAT64 hosts frequently cannot reach public resolvers
    # (e.g. 8.8.8.8) through their firewall, so we forward to whatever the host
    # itself uses. When NetworkManager runs in dnsmasq mode /etc/resolv.conf points
    # at a loopback stub and the real upstream servers live in no-stub-resolv.conf.
    # The `|| true` matters under set -e: awk exits non-zero when the file is
    # absent (e.g. no-stub-resolv.conf only exists when NM is in dnsmasq mode),
    # and 2>/dev/null hides the message but not the status, so a bare assignment
    # would abort the whole host-configure run. Fall through to the next source.
    local upstreams="${NAT64_DNS64_UPSTREAM:-}"
    if [[ -z "${upstreams//[[:space:]]/}" ]]; then
        upstreams=$(awk '/^nameserver/ && $2 != "127.0.0.1" && $2 != "::1" {print $2}' /run/NetworkManager/no-stub-resolv.conf 2>/dev/null || true)
    fi
    if [[ -z "${upstreams//[[:space:]]/}" ]]; then
        upstreams=$(awk '/^nameserver/ && $2 != "127.0.0.1" && $2 != "::1" {print $2}' /etc/resolv.conf 2>/dev/null || true)
    fi
    if [[ -z "${upstreams//[[:space:]]/}" ]]; then
        # Fall back to a public resolver so DNS64 still comes up, but warn loudly:
        # on a firewalled NAT64 host 8.8.8.8 is usually unreachable and every DNS64
        # lookup will time out. Set NAT64_DNS64_UPSTREAM to fix this deliberately.
        echo "WARNING: could not discover any host upstream resolver for DNS64;" >&2
        echo "WARNING: falling back to 8.8.8.8, which is often unreachable on a" >&2
        echo "WARNING: firewalled NAT64 host. Set NAT64_DNS64_UPSTREAM to override." >&2
        upstreams=8.8.8.8
    fi
    echo "DNS64 upstream resolvers: ${upstreams}"

    # NOTE: this unbound instance is a non-validating DNS64 forwarder. dns64-synthall
    # rewrites AAAA answers into ${NAT64_PREFIX}, which is fundamentally incompatible
    # with DNSSEC AAAA validation, and it implicitly trusts the host's upstream
    # resolvers (discovered above). That trust model matches the rest of dev-scripts
    # (a lab/CI tool on a controlled network); do not treat this resolver as a
    # security boundary.

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

# Bounded dummy-interface name for a libvirt network. Linux caps interface names
# at 15 chars (IFNAMSIZ-1); a long ${net} would overflow "${net}-dmy", the create
# would fail and the bridge would be left without carrier (so its IPv6 never comes
# up). Truncate ${net} so the "-dmy" suffix always fits. Used by both the create
# and cleanup paths so they always agree on the name.
function _nat64_dummy_ifname() {
    echo "${1:0:11}-dmy"
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

    # net-info (above) also succeeds for a defined-but-inactive network, for which
    # net-destroy exits non-zero ("network is not active"); tolerate that under
    # set -e so an inactive extra network does not abort the run.
    sudo virsh net-destroy "${net}" 2>/dev/null || true
    sudo virsh net-undefine "${net}"
    sudo virsh net-define "${xml}"
    # net-undefine clears the autostart flag; restore it so the
    # network still comes up after a host reboot.
    sudo virsh net-autostart "${net}"
    sudo virsh net-start "${net}"

    # net-destroy drops the bridge; restore a dummy for carrier and addr_gen_mode=0
    # so the network's IPv6 address comes up before the VMs provide carrier (needed
    # for IPv6 on EL9).
    local dmy
    dmy=$(_nat64_dummy_ifname "${net}")
    sudo ip link add name "${dmy}" up master "${net}" type dummy 2>/dev/null || true
    echo 0 | sudo dd of="/proc/sys/net/ipv6/conf/${net}/addr_gen_mode" 2>/dev/null || true
}

# Embed an IPv4 address inside a NAT64 /96 prefix (RFC 6052), e.g.
# nat64_embed_v4 "fd00:64::/96" 192.168.111.1 -> fd00:64::c0a8:6f01. Only the /96
# form is supported (the documented default); with /96 the IPv4 simply occupies the
# last 32 bits, i.e. the two hex groups appended after the prefix's trailing "::".
# Other prefix lengths interleave the v4 octets differently and are not used by
# dev-scripts.
function nat64_embed_v4() {
    local prefix="${1%/*}"   # strip the /96 mask -> e.g. fd00:64::
    local o1 o2 o3 o4
    IFS='.' read -r o1 o2 o3 o4 <<<"$2"
    # Pack the four octets into two 16-bit groups and print them without leading
    # zeros, matching IPv6's canonical hextet form (e.g. 10.0.0.255 -> a00:ff).
    # 10# forces base-10 so an octet written with a leading zero (e.g. 011) is not
    # mis-parsed as octal (and 08/09 don't abort as "invalid octal").
    printf '%s%x:%x\n' "${prefix}" "$(( (10#$o1 << 8) | 10#$o2 ))" "$(( (10#$o3 << 8) | 10#$o4 ))"
}

# When running an IPv6-only cluster via NAT64, the in-cluster Ironic runs as
# IPv6-only pods (hostNetwork on v6-only nodes) and cannot reach the BMC emulators
# at their IPv4 baremetal address. Rewrite the generated node BMC addresses so both
# the bootstrap Ironic and the pivoted in-cluster Ironic can control the nodes:
#   - redfish (sushy) also listens on IPv6, so point it at the host's native IPv6
#     baremetal address (paired with nat64_fixup_sushy_cert for its TLS SAN).
#   - ipmi (vbmc) is IPv4-only, so point it at the NAT64-synthesized form of its
#     IPv4 address; TAYGA translates that back to IPv4 (needs a ULA NAT64_PREFIX,
#     enforced in common.sh, since the well-known prefix cannot carry RFC1918).
# This makes BMC_DRIVER=mixed (and ipmi) work, not just the redfish drivers.
function nat64_fixup_bmc_addresses() {
    local v4host v6host embed
    v4host=$(nth_ip "${EXTERNAL_SUBNET_V4}" 1)
    v6host=$(nth_ip "${EXTERNAL_SUBNET_V6}" 1)
    if [[ -z "${v4host}" || -z "${v6host}" ]]; then
        echo "nat64_fixup_bmc_addresses: missing v4/v6 baremetal host address, skipping"
        return 0
    fi
    # NAT64-embedded form of the IPv4 baremetal address, used for ipmi BMCs. Unused
    # (and harmless) when every node is redfish, so it is always computed.
    embed=$(nat64_embed_v4 "${NAT64_PREFIX}" "${v4host}")
    echo "Rewriting node BMC addresses for NAT64: redfish -> [${v6host}], ipmi -> [${embed}]..."
    local f tmp
    for f in "${NODES_FILE}" "${NODES_FILE}.orig" "${EXTRA_NODES_FILE:-}" "${ARM_NODES_FILE:-}"; do
        [[ -n "${f}" && -f "${f}" ]] || continue
        tmp="${f}.nat64"
        # Per-node, driver-aware literal (non-regex) host replacement on the "//host:"
        # token. The address? == null guard skips nodes without a BMC address (e.g. a
        # manually-edited inventory) instead of aborting jq on a null/string divide.
        # ipmi nodes get the NAT64-embedded address; everything else (redfish,
        # redfish-virtualmedia) gets the native IPv6 host. On success copy back through
        # the original file (preserving its mode/owner rather than replacing it with a
        # fresh-umask temp via mv); always remove the temp so a jq failure does not
        # strand a partial ".nat64" file.
        if jq --arg old "//${v4host}:" --arg v6 "//[${v6host}]:" --arg embed "//[${embed}]:" \
            '.nodes[]? |= (
                if (.driver_info.address? == null) then .
                else .driver_info.address =
                    (if .driver == "ipmi"
                     then (.driver_info.address / $old | join($embed))
                     else (.driver_info.address / $old | join($v6)) end)
                end)' \
            "${f}" > "${tmp}"; then
            # Overwrite in place with sudo: ${f} may be root-owned (written by an
            # earlier privileged step) while its directory is user-writable, so a
            # plain ">" redirect fails with EACCES. cp onto the existing file also
            # keeps its original mode/owner rather than replacing it with a
            # fresh-umask temp (which a plain "mv" would have done).
            sudo cp "${tmp}" "${f}"
        fi
        rm -f "${tmp}"
    done
}

# Regenerate the sushy-tools BMC emulator TLS certificate so it is valid for the
# host's IPv6 baremetal address in addition to its IPv4 one. vm-setup only
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
    # Probe for the cert/key under sudo: ${WORKING_DIR}/virtualbmc is root-owned and
    # root-only (drwxr-x---), so the invoking user cannot traverse it and a plain
    # "[[ -f ]]" would report the files missing even when they exist, silently
    # skipping the fixup (leaving sushy serving an IPv4-only cert that the IPv6-only
    # in-cluster Ironic rejects). The rest of this function already uses sudo.
    if ! sudo test -f "${cert}" || ! sudo test -f "${key}" || [[ -z "${v6host}" ]]; then
        echo "nat64_fixup_sushy_cert: sushy cert/key or IPv6 host address missing, skipping"
        return 0
    fi

    # Already valid for the IPv6 address? Nothing to do. Use openssl's own SAN
    # matching (-checkip) rather than grepping the text dump: openssl renders IPv6
    # SANs in uncompressed form, so a substring match for the compressed address
    # never matched and the cert was needlessly regenerated on every run.
    if sudo openssl x509 -in "${cert}" -noout -checkip "${v6host}" >/dev/null 2>&1; then
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
    # NOTE: deliberately do NOT "rm -rf /etc/coredns" here. This helper runs on
    # every configure_dns64 call, and /etc/coredns may hold an unrelated host-owned
    # CoreDNS configuration. Stopping/removing our own service is enough to free the
    # DNS64 port.
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
        sudo ip link del "$(_nat64_dummy_ifname "${net}")" 2>/dev/null || true
    done
    # Remove the legacy baremetal dummy name used by earlier revisions
    sudo ip link del bm-ipv6-dummy 2>/dev/null || true

    # Remove dnsmasq DNS64 forwarding config
    sudo rm -f "${NAT64_DNSMASQ_CONF}"
    if systemctl is-active --quiet NetworkManager; then
        sudo systemctl reload NetworkManager
    fi

    # Stop and disable the TAYGA systemd service
    if sudo systemctl is-active --quiet "${NAT64_TAYGA_SERVICE}.service" 2>/dev/null; then
        sudo systemctl stop "${NAT64_TAYGA_SERVICE}.service"
    fi
    sudo systemctl disable "${NAT64_TAYGA_SERVICE}.service" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/${NAT64_TAYGA_SERVICE}.service"
    sudo systemctl daemon-reload
    # Kill any stray bare tayga daemon FIRST, then tear down the TUN device: tayga
    # holds the TUN open, so --rmtun before the process is gone leaves it orphaned.
    # Match by exact process name (the cmdline is "/usr/sbin/tayga ...", so an
    # "^tayga" -f pattern never matched). Delete the device explicitly as a backstop
    # in case --rmtun fails (e.g. the tayga binary is already gone).
    sudo pkill -x tayga 2>/dev/null || true
    sudo tayga --rmtun 2>/dev/null || true
    sudo ip link del "${NAT64_TUN_INTERFACE}" 2>/dev/null || true

    # Drop the permanent firewalld trusted-zone binding for the TUN (added in
    # configure_tayga so translated ipmi BMC traffic is not dropped). The runtime
    # binding disappears with the interface; remove the persisted one too.
    if command -v firewall-cmd >/dev/null 2>&1 && sudo firewall-cmd --state >/dev/null 2>&1; then
        sudo firewall-cmd --permanent --zone=trusted --remove-interface="${NAT64_TUN_INTERFACE}" 2>/dev/null || true
        sudo firewall-cmd --reload 2>/dev/null || true
    fi

    # Remove NAT64 routes
    sudo ip route del "${NAT64_V4_POOL}" dev "${NAT64_TUN_INTERFACE}" 2>/dev/null || true
    sudo ip -6 route del "${NAT64_PREFIX}" dev "${NAT64_TUN_INTERFACE}" 2>/dev/null || true

    # Remove iptables masquerade rule
    sudo iptables -t nat -D POSTROUTING -s "${NAT64_V4_POOL}" -j MASQUERADE 2>/dev/null || true

    # Remove the IPv6 FORWARD rules added by 02_configure_host.sh for NAT64
    sudo ip6tables -D FORWARD --in-interface "${BAREMETAL_NETWORK_NAME}" -j ACCEPT 2>/dev/null || true
    sudo ip6tables -D FORWARD --out-interface "${BAREMETAL_NETWORK_NAME}" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

    # Clean up TAYGA data and config
    sudo rm -rf "${NAT64_TAYGA_DATA_DIR}"
    sudo rm -f "${NAT64_TAYGA_CONF}"

    echo "NAT64/DNS64 cleanup complete"
}
