#!/usr/bin/env bash
set -euxo pipefail

# Tears down the optional LLDP ToR switch emulation deployed by
# configure_lldp_tor.sh. Tolerant of a missing service / config so it can
# run unconditionally from host_cleanup.sh. The lldpd package stays
# installed.

sudo systemctl disable --now lldpd || true

sudo rm -f /etc/lldpd.d/lldp-tor.conf
