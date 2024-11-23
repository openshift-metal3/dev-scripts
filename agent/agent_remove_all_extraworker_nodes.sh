#!/usr/bin/env bash
#
# This script removes extraworker nodes from the cluster.
#
# Each node is first cordoned or marked as unschedulable.
# The node is then drained and deleted from the cluster.
# The VM is then shutdown.
#
# To refresh the VM so that it can be reused to add
# a new node, its disk is reinitialized to be empty
# and the agent ISO mounted as a cdrom is removed.
#
# In this way, one can repeated run
#
#   make agent_add_node
#   make agent_remove_node
#
# to add and remove extraworker nodes. This provides
# an easy way to test adding nodes during day 2.
#

set -euo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

source $SCRIPTDIR/common.sh

export KUBECONFIG=$OCP_DIR/auth/kubeconfig

for (( n=0; n<${NUM_EXTRA_WORKERS}; n++ ))
do
    node="extraworker-${n}"
    nodeLibvirt="${CLUSTER_NAME}_extraworker_${n}"
    oc adm cordon "$node" || true
    oc adm drain "$node" --force --ignore-daemonsets || true
    oc delete node "$node" || true
    sudo virsh destroy "$nodeLibvirt" || true

    sleep 5s

    sudo qemu-img create -f qcow2 "/opt/dev-scripts/pool/${nodeLibvirt}.qcow2" 100G || true
    sudo virt-xml "$nodeLibvirt" --remove-device --disk target=sdc || true
done
 