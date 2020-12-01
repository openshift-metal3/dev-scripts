#!/bin/bash

source common.sh
source network.sh
source utils.sh

BOOTSTRAP_VM_IP=$(bootstrap_ip)
echo "Attempting to follow $1 on ${BOOTSTRAP_VM_IP} ..."
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no core@${BOOTSTRAP_VM_IP} journalctl -b -f -u $1
