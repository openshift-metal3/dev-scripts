#!/bin/bash

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../../" && pwd )"
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/agent/e2e/agent-tui/utils.sh

set +x
shopt -s nocasematch

node_name=$1

# The following commands sends key presses through "virsh send-key" to interact
# with agent-tui
if [[ "$node_name" == "${AGENT_RENDEZVOUS_NODE_HOSTNAME}" ]]; then
    pressDown "Save Rendezvous IP" 1 "$node_name"
    pressDown "This is the rendezvous node" 1 "$node_name"
    pressEnter "This is the rendezvous node" "" "$node_name"
    pressEnter "" "" "$node_name"
    pressEnter "Continue" "" "$node_name"
else
    # Retrieves the rendezvousIP and automatically inputs it into the TUI text field
    # on all other nodes to ensure proper cluster joining.
    rendezvousIP=$(getRendezvousIP)

    pressKeys "Entering IP address" "$rendezvousIP" "$node_name"
    pressDown "Save Rendezvous IP" 1 "$node_name"
    pressEnter "" "" "$node_name"
    pressEnter "Save and Continue" "" "$node_name"
fi
