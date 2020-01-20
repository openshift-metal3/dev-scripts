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
    fssh core@${MASTER} sudo systemctl restart NetworkManager
    sleep 5
    fssh core@${MASTER} hostname
    MDNS_POD=$(fssh core@${MASTER} sudo crictl pods | grep mdns | awk '{print $1}')
    fssh core@${MASTER} sudo crictl stopp ${MDNS_POD}
    fssh core@${MASTER} sudo crictl rmp ${MDNS_POD}
    sleep 5
    fssh core@${MASTER} cat /etc/mdns/config.hcl | grep host
done

fssh core@${BOOTSTRAP_IP} sudo sed -i \"1s/^/nameserver ${DNS_VIP}\\n/\" /etc/resolv.conf
