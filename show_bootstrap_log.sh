#!/bin/bash

source common.sh

BOOTSTRAP_VM_IP=$(sudo virsh net-dhcp-leases ${BAREMETAL_NETWORK_NAME} \
                      | grep -v master \
                      | grep "ip${IP_STACK}" \
                      | tail -n1 \
                      | awk '{print $5}' \
                      | sed -e 's/\(.*\)\/.*/\1/')

echo "Attempting to follow $1 on ${BOOTSTRAP_VM_IP} ..."
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no core@${BOOTSTRAP_VM_IP} journalctl -b -f -u $1
