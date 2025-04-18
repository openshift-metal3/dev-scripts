#!/bin/bash

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../../" && pwd )"
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/agent/e2e/agent-tui/utils.sh

set +x
shopt -s nocasematch

node_name=$1

# The following commands sends key presses through "virsh send-key" to interact
# with agent-tui
if [[ "$node_name" == "${CLUSTER_NAME}_master_0" ]]; then
    pressDown "Save Rendezvous IP" 1
    pressDown "This is the rendezvous node" 1
    pressEnter "This is the rendezvous node"
    pressEnter "" 
    pressEnter "Continue"
else
    # Since master_0 is the first node to boot and is correctly set as the rendezvous node,
    # this else block retrieves the rendezvousIP and automatically inputs it into the TUI text field
    # on all other nodes to ensure proper cluster joining.
    rendezvousIP=$(getRendezvousIP)

    pressKeys "Entering IP address" "$rendezvousIP" "$node_name"
    pressDown "Save Rendezvous IP" 1 "$node_name"
    pressEnter "" "" "$node_name"
    pressEnter "Continue" "" "$node_name"
fi
