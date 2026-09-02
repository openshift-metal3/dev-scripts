#!/bin/bash
#
# test-static-ip.sh - configuration step of the 'static_ip' e2e test case.
#
# Drives the agent TUI (and nmtui within it) via "virsh send-key" to assign a
# static IPv4 address and hostname to a single node, creating a NEW
# NetworkManager connection so coreos-installer's --copy-network preserves the
# static config into the installed system. The matching verification step runs
# at the end of the install (see test_case_verify_static_ip in
# agent/06_agent_create_cluster.sh).
#
# Example configuration applied to a node:
#   ┌───────────────┬─────────────────┐
#   │ Interface     │ enp2s0          │
#   │ IP address    │ <node_ip>/24    │
#   │ Gateway       │ 192.168.111.1   │
#   │ DNS server    │ 192.168.111.1   │
#   │ Hostname      │ <node_hostname> │
#   │ Rendezvous IP │ <rendezvous IP> │
#   └───────────────┴─────────────────┘
#
# Usage: test-static-ip.sh <node_name> <node_ip> <node_hostname>
#
SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../../" && pwd )"
source "$SCRIPTDIR/common.sh"
source "$SCRIPTDIR/agent/common.sh"
source "$SCRIPTDIR/agent/e2e/agent-tui/utils.sh"

set +x

node_name=$1
node_ip=$2
node_hostname=$3

# All interaction below is via "virsh send-key" into agent-tui and nmtui.

# Phase 1: from the TUI first screen navigate to <Configure Network>.
pressDown "Navigate to <Configure Network>" 3 "$node_name"
pressEnter "Select '<Configure Network>'" "" "$node_name"

# Phase 2: add a new Ethernet connection with a static IP in nmtui. A NEW
# connection (not editing the existing one) gives a .nmconnection file with a
# birth time after agent-tui start, which triggers coreos-installer --copy-network.
pressEnter "Select 'Edit a connection'" "" "$node_name"

# Tab from the connection list to the <Add> button.
pressTab "Goto <Add> button" 1 "$node_name"
pressEnter "Select '<Add>' button" "" "$node_name"

# Connection type dialog: select Ethernet, then tab to <Create> and confirm.
pressDown "Select Ethernet" 1 "$node_name"
pressTab "Goto <Cancel> button" 1 "$node_name"
pressTab "Goto <Create> button" 1 "$node_name"
pressEnter "Create new Ethernet connection" "" "$node_name"

# Leave default profile name, tab to the Device field and enter the interface.
pressTab "Goto Device field" 1 "$node_name"
pressKeys "Enter device name" "enp2s0" "$node_name"

# Tab past ETHERNET/802.1X <Show> to the IPv4 CONFIGURATION mode.
pressTab "Goto IPv4 CONFIGURATION mode" 3 "$node_name"
pressEnter "Open IPv4 mode selector" "" "$node_name"
# From Automatic, Manual is two DOWNs (Disabled, Automatic, Link-Local, Manual).
pressDown "Select Manual" 2 "$node_name"
pressEnter "Confirm Manual" "" "$node_name"

# Expand <Show> to reveal the address fields.
pressTab "Goto <Show>" 1 "$node_name"
pressEnter "Expand IPv4 details" "" "$node_name"

# Enter the static IP in the Addresses field.
pressTab "Goto Addresses <Add...>" 1 "$node_name"
pressEnter "Activate Addresses field" "" "$node_name"
pressKeys "Enter static IP address" "${node_ip}/24" "$node_name"

# Tab past <Remove>/<Add...> to the Gateway field.
pressTab "Goto Gateway field" 3 "$node_name"
pressKeys "Enter gateway" "192.168.111.1" "$node_name"

# Enter the DNS server.
pressTab "Goto DNS servers <Add...>" 1 "$node_name"
pressEnter "Activate DNS servers field" "" "$node_name"
pressKeys "Enter DNS server" "192.168.111.1" "$node_name"

# Tab past the remaining DNS/search/routing/IPv6 options and checkboxes to <OK>
# (14 stops: <Remove>, <Add...>, Search domains, Routing, 4 route/DNS checkboxes,
# IPv6 <Automatic>/<Show>, 2 connect checkboxes, <Cancel>, <OK>).
pressTab "Goto <OK> button" 14 "$node_name"
pressEnter "Select '<OK>' button" "" "$node_name"

# Phase 3: back at the connection list, go Back to the main menu and activate
# the new static connection (NM auto-deactivates the old DHCP one).
pressTab "Goto <Back> button" 4 "$node_name"
pressEnter "Select '<Back>' button" "" "$node_name"
pressDown "Select 'Activate a connection'" 1 "$node_name"
pressEnter "Select 'Activate a connection' menu item" "" "$node_name"
# Our new static connection is 2 DOWN (past the active '* Wired connection 2').
pressDown "Select 'Ethernet connection 1'" 2 "$node_name"
pressEnter "Activate new static connection" "" "$node_name"
sleep 3

# Phase 4: set the system hostname in nmtui.
pressTab "Goto <Back> button" 2 "$node_name"
pressEnter "Select '<Back>' button" "" "$node_name"
pressDown "Select 'Set system hostname'" 1 "$node_name"
pressEnter "Select 'Set system hostname' menu item" "" "$node_name"

# Clear any existing hostname (End then Ctrl+U) and enter the new one.
pressKey "Goto end of hostname field" KEY_END 1 "$node_name"
echo "Clear hostname field"
sudo virsh send-key "$node_name" KEY_LEFTCTRL KEY_U
sleep 1
pressKeys "Enter hostname" "$node_hostname" "$node_name"

# Tab past <Cancel> to <OK> and confirm.
pressTab "Goto <OK> button" 2 "$node_name"
pressEnter "Confirm hostname" "" "$node_name"

# Phase 5: exit nmtui back to the TUI first screen (Quit is 2 DOWN from hostname).
pressDown "Select Quit" 2 "$node_name"
pressEnter "Select 'Quit' menu item" "" "$node_name"
pressEsc "Esc from network tree view" 2 "$node_name"
sleep 3

# Wait for TUI checks to update after network reconfiguration.
sleep 10

# Phase 6: save the rendezvous IP on the TUI first screen. All nodes enter the
# same rendezvous IP; the rendezvous node recognizes it as its own.
rendezvousIP=$(getRendezvousIP)
pressKeys "Entering rendezvous IP address" "$rendezvousIP" "$node_name"
# After typing, the first TAB is absorbed, so 2 TABs reach <Save rendezvous IP>.
pressTab "Goto <Save rendezvous IP>" 2 "$node_name"
pressEnter "" "" "$node_name"
pressEnter "Save and Continue" "" "$node_name"
