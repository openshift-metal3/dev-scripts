#!/bin/bash

BOOTSTRAP_VM_IP=$(sudo virsh net-dhcp-leases baremetal | grep -v master | grep ipv4 | tail -n1 | sed -e 's/.*\(192.*\)\/.*/\1/')
echo "Attempting to follow openshift on ${BOOTSTRAP_VM_IP} ..."
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no core@${BOOTSTRAP_VM_IP} journalctl -b -f -u openshift.service
