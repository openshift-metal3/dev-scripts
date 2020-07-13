#!/bin/bash

source common.sh

if [[ "${IP_STACK}" == "v6" ]]; then
    pref_ip=ipv6
else
    pref_ip=ipv4
fi

BOOTSTRAP_VM_IP=$(sudo virsh net-dhcp-leases ${BAREMETAL_NETWORK_NAME} \
                      | grep -v master \
                      | grep "${pref_ip}" \
                      | tail -n1 \
                      | awk '{print $5}' \
                      | sed -e 's/\(.*\)\/.*/\1/')

echo "Attempting to follow $1 on ${BOOTSTRAP_VM_IP} ..."
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no core@${BOOTSTRAP_VM_IP} journalctl -b -f -u $1
