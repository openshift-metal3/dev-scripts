#!/usr/bin/env bash
set -euxo pipefail

bgp_dir="$(dirname "$(readlink -f "$0")")"
# shellcheck disable=SC1091
source "${bgp_dir}/../common.sh"

# Tears down the optional top-of-rack BGP speaker deployed by
# configure_bgp_tor.sh. Tolerant of a missing container / firewall rule so
# it can run unconditionally from host_cleanup.sh.

BGP_TOR_NAME="bgp-tor"
BGP_TOR_DIR="${WORKING_DIR}/bgp-tor"

sudo podman rm -f "${BGP_TOR_NAME}" || true

sudo firewall-cmd --zone=libvirt --permanent --remove-port=179/tcp || true
sudo firewall-cmd --zone=libvirt --remove-port=179/tcp || true

rm -rf "${BGP_TOR_DIR}"
