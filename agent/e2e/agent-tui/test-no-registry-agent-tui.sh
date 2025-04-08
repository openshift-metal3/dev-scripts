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
    pressDown "Designate this node as the Rendezvous node by selecting one of its IPs" 1
    pressEnter "Designate this node as the Rendezvous node by selecting one of its IPs"
    pressEnter "" 
    pressEnter "Continue with installation"
else
    # As master_0 is the first node to boot and the above condition
    # correctly sets the master_0 node as the rendezvous node,
    # this else block then determines the rendezvousIP and 
    # sets the rendezvousIP into all other nodes by typing 
    # automatically in the TUI textfield.
    rendezvousIP=$(getRendezvousIP)

    typeIPAddress "Entering IP address" "$rendezvousIP" "$node_name"
    pressDown "Save Rendezvous IP" 1 "$node_name"
    pressEnter "" "" "$node_name"
    pressEnter "Continue with installation" "" "$node_name"
fi
