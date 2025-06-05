#!/bin/bash

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../../" && pwd )"
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/agent/e2e/agent-tui/utils.sh
set +x

GOOD_DNS_IP=$1
OCP_VERSION=$2

### Prereq: create an agent ISO using an incorrect DNS address in the agent-config.yaml
### This can be done by setting AGENT_E2E_TEST_TUI_BAD_DNS to true in config_<user>.sh

# The following commands sends key presses through "virsh send-key" to interact
# with agent-tui and nmtui to correct the DNS IP address.

pressEnter "Select '<Configure network>' button"
pressEnter "Select 'Edit a connection'"
pressEnter "Select 'enp2s0'"

pressTab "Goto DNS field" 10
pressBackspace "Cleanup DNS previous value" 15
pressKeys "Insert correct DNS address" "${GOOD_DNS_IP}"
pressTab "Goto <OK> button" 14

# if [ $IP_STACK = "v6" ]; then
#   pressTab "Goto DNS field" 12
#   pressBackspace "Cleanup DNS previous value" 24
#   pressKeys "Insert correct DNS address" "${GOOD_DNS_IP}"
#   pressTab "Goto <OK> button" 12
# fi

# if [ $IP_STACK = "v4v6" ]; then
#   pressTab "Goto IPv4 DNS field" 10
#   pressBackspace "Cleanup DNS previous IPv4 value" 15
#   pressKeys "Insert correct IPv4 DNS address" "${GOOD_DNS_IP}"
#   pressTab "Goto IPv6 DNS field" 15
#   pressBackspace "Cleanup DNS previous IPv6 value" 24
#   pressKeys "Insert correct IPv6 DNS address" "${GOOD_DNS_IP2}"
#   pressTab "Goto <OK> button" 12
# fi

pressEnter "Select '<OK>' button"
pressTab "Goto <Back> button" 4
pressEnter "Select '<Back>' button"
pressDown "Select 'Activate a connection'" 1
pressEnter "Select 'Activate a connection' menu item"
pressDown "Select 'enp2s0' to deactivate" 1
pressEnter "Deactivate 'enp2s0'"
sleep 3
pressDown "Select 'enp2s0' to reactivate" 1
pressEnter "Reactivate 'enp2s0'"
sleep 3
pressTab "Goto <Back> button" 2
pressEnter "Select '<Back>' button'"

# Since ocp 4.16, the nmtui has an additional menu entry "Radio" in the main panel
# so it's necessary an additional step
numStepsToQuit=2
if ! is_lower_version "${OCP_VERSION}" "4.16"; then
    numStepsToQuit=3
fi
pressDown "Select Quit" ${numStepsToQuit}

pressEnter "Select 'Quit' menu item"
pressEsc "Esc from network tree view" 2
sleep 3
pressLeft "Goto <Quit> button to exit agent-tui" 1

# wait for check to update, to visually see the release image
# check change to passing.
sleep 10
pressEnter "Exit agent-tui"
