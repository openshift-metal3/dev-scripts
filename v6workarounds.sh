#!/bin/bash

if [ $# != 2 ] ; then
    echo "Usage: ./v6workarounds.sh <bootstrap-ip> <dns-vip>"
    exit 1
fi

# The BOOTSTRAP_IP isn't always the same, so we have to take it as an argument
BOOTSTRAP_IP="$1"
DNS_VIP=$2

fssh() {
    ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $@
}

fssh core@${BOOTSTRAP_IP} sudo sed -i \"1s/^/nameserver ${DNS_VIP}\\n/\" /etc/resolv.conf
