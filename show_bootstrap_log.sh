#!/bin/bash

BOOTSTRAP_VM_IP="172.22.0.2"
echo "Attempting to follow $1 on bootstrap node ..."
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no core@${BOOTSTRAP_VM_IP} journalctl -b -f -u $1
