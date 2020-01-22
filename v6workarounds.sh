#!/bin/bash

if [ $# != 2 ] ; then
    echo "Usage: ./v6workarounds.sh <bootstrap-ip> <dns-vip>"
    exit 1
fi

# The BOOTSTRAP_IP isn't always the same, so we have to take it as an argument
BOOTSTRAP_IP="$1"
DNS_VIP=$2

MASTER_IPS="fd2e:6f44:5dd8:c956::14 fd2e:6f44:5dd8:c956::15 fd2e:6f44:5dd8:c956::16"

fssh() {
    ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $@
}

for MASTER in ${MASTER_IPS} ; do
    # haproxy not configured to listen on IPv6
    fssh core@${MASTER} sudo sed -i \"s/bind :7443/bind :::7443 v4v6/\" /etc/haproxy/haproxy.cfg
    fssh core@${MASTER} sudo sed -i \"s/bind :50936/bind :::50936 v4v6/\" /etc/haproxy/haproxy.cfg
done

fssh core@${BOOTSTRAP_IP} sudo sed -i \"1s/^/nameserver ${DNS_VIP}\\n/\" /etc/resolv.conf
