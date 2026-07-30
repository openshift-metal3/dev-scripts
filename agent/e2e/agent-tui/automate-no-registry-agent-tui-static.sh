#!/bin/bash

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../../" && pwd )"
source "$SCRIPTDIR/common.sh"
source "$SCRIPTDIR/agent/common.sh"
source "$SCRIPTDIR/agent/e2e/agent-tui/utils.sh"

set +x

node_name=$1
node_ip=$2
node_hostname=$3

# The following commands send key presses through "virsh send-key" to interact
# with agent-tui and nmtui to configure static networking.

#
# Phase 1: Navigate from TUI first screen to nmtui
# The TUI first screen has: Rendezvous IP field, <Save rendezvous IP>,
# <This is the rendezvous node>, and <Configure Network> at the bottom.
#
pressDown "Navigate to <Configure Network>" 3 "$node_name"
pressEnter "Select '<Configure Network>'" "" "$node_name"

#
# Phase 2: Add a new Ethernet connection with static IP in nmtui
# Creating a NEW connection (rather than editing the existing one) ensures
# a new .nmconnection file is created with a birth time after agent-tui start.
# This triggers the --copy-network flag in coreos-installer, which preserves
# the static networking config into the installed system.
#
# nmtui opens with: "Edit a connection", "Activate a connection",
# "Set system hostname", "Radio" (4.16+), "Quit"
#
pressEnter "Select 'Edit a connection'" "" "$node_name"

# Tab from connection list to <Add> button.
# Connection list is one widget; Tab goes to buttons: <Add>, <Edit>, <Delete>, <Back>
pressTab "Goto <Add> button" 1 "$node_name"
pressEnter "Select '<Add>' button" "" "$node_name"

# New Connection type dialog: DSL is selected by default.
# Navigate down to Ethernet, then tab past <Cancel> to <Create> and confirm.
pressDown "Select Ethernet" 1 "$node_name"
pressTab "Goto <Cancel> button" 1 "$node_name"
pressTab "Goto <Create> button" 1 "$node_name"
pressEnter "Create new Ethernet connection" "" "$node_name"

# Edit Connection form opens with cursor on Profile name field.
# Leave default profile name, tab to Device field and enter interface name.
pressTab "Goto Device field" 1 "$node_name"
pressKeys "Enter device name" "enp2s0" "$node_name"

# Tab past ETHERNET <Show>, 802.1X SECURITY <Show> to IPv4 <Automatic>
pressTab "Goto IPv4 CONFIGURATION mode" 3 "$node_name"
pressEnter "Open IPv4 mode selector" "" "$node_name"
# Modes are: Disabled, Automatic, Link-Local, Manual
# From Automatic, Manual is two DOWNs
pressDown "Select Manual" 2 "$node_name"
pressEnter "Confirm Manual" "" "$node_name"

# After selecting Manual, expand <Show> to reveal address fields.
# From the mode selector, <Show> is the next tab stop.
pressTab "Goto <Show>" 1 "$node_name"
pressEnter "Expand IPv4 details" "" "$node_name"

# Tab to the Addresses <Add...> field and enter the static IP.
pressTab "Goto Addresses <Add...>" 1 "$node_name"
pressEnter "Activate Addresses field" "" "$node_name"
pressKeys "Enter static IP address" "${node_ip}/24" "$node_name"

# Tab past <Remove> and <Add...> to Gateway field
pressTab "Goto Gateway field" 3 "$node_name"
pressKeys "Enter gateway" "192.168.111.1" "$node_name"

# Tab to DNS servers <Add...> field
pressTab "Goto DNS servers <Add...>" 1 "$node_name"
pressEnter "Activate DNS servers field" "" "$node_name"
pressKeys "Enter DNS server" "192.168.111.1" "$node_name"

# Tab to <OK> button
# From DNS servers, tab past: <Remove>, <Add...>, Search domains <Add...>,
# Routing (No custom routes) <Edit...>,
# [ ] Never use this network for default route,
# [ ] Ignore automatically obtained routes,
# [ ] Ignore automatically obtained DNS parameters,
# [ ] Require IPv4 addressing for this connection,
# IPv6 CONFIGURATION <Automatic> <Show>,
# [X] Automatically connect, [X] Available to all users,
# <Cancel>, <OK>
pressTab "Goto <OK> button" 14 "$node_name"
pressEnter "Select '<OK>' button" "" "$node_name"

#
# Phase 3: Activate the new static connection
# After OK we're back at the connection list. Go Back to main menu,
# then activate the new connection (which deactivates the old DHCP one).
#
pressTab "Goto <Back> button" 4 "$node_name"
pressEnter "Select '<Back>' button" "" "$node_name"
pressDown "Select 'Activate a connection'" 1 "$node_name"
pressEnter "Select 'Activate a connection' menu item" "" "$node_name"
# Activate a connection list layout:
#   Ethernet (enp1s0)
#     Wired connection 1        <- cursor starts here
#   Ethernet (enp2s0)
#   * Wired connection 2        <- active DHCP (DOWN 1)
#     Ethernet connection 1     <- our new static (DOWN 2)
# Navigate down 2 to our new static connection and activate it.
# NM auto-deactivates the old DHCP connection on the same device.
pressDown "Select 'Ethernet connection 1'" 2 "$node_name"
pressEnter "Activate new static connection" "" "$node_name"
sleep 3

#
# Phase 4: Set system hostname in nmtui
# After "Activate a connection" Back, we're at the main menu.
# Menu items: "Edit a connection", "Activate a connection" (cursor here),
# "Set system hostname", "Radio" (4.16+), "Quit"
#
pressTab "Goto <Back> button" 2 "$node_name"
pressEnter "Select '<Back>' button" "" "$node_name"
pressDown "Select 'Set system hostname'" 1 "$node_name"
pressEnter "Select 'Set system hostname' menu item" "" "$node_name"

# Clear any existing hostname and enter the new one.
# The dialog has: hostname text field, <Cancel>, <OK>.
# Press End to ensure cursor is at end of any existing text,
# then Ctrl+U to clear the line.
pressKey "Goto end of hostname field" KEY_END 1 "$node_name"
echo "Clear hostname field"
sudo virsh send-key "$node_name" KEY_LEFTCTRL KEY_U
sleep 1
pressKeys "Enter hostname" "$node_hostname" "$node_name"

# Tab past <Cancel> to <OK> and confirm
pressTab "Goto <OK> button" 2 "$node_name"
pressEnter "Confirm hostname" "" "$node_name"

#
# Phase 5: Exit nmtui back to TUI first screen
# After setting hostname, we're back at the main menu on "Set system hostname".
# From here: "Radio" is 1 down, "Quit" is 2 down.
#
pressDown "Select Quit" 2 "$node_name"
pressEnter "Select 'Quit' menu item" "" "$node_name"
pressEsc "Esc from network tree view" 2 "$node_name"
sleep 3

# Wait for TUI checks to update after network reconfiguration
sleep 10

#
# Phase 6: Save rendezvous IP on the TUI first screen
# After returning from nmtui, cursor is back on the Rendezvous IP field.
# All nodes enter the same rendezvous IP. The rendezvous node recognizes
# the IP as its own; other nodes use it to find the rendezvous.
#
rendezvousIP=$(getRendezvousIP)
pressKeys "Entering rendezvous IP address" "$rendezvousIP" "$node_name"
# After typing in the text field, the first TAB is absorbed, so we need
# 2 TABs to reach <Save rendezvous IP>: 1 absorbed + 1 to <Save>
pressTab "Goto <Save rendezvous IP>" 2 "$node_name"
pressEnter "" "" "$node_name"
pressEnter "Save and Continue" "" "$node_name"
