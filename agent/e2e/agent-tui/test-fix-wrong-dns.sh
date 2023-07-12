#!/bin/bash

CLUSTER_NAME=$1
GOOD_DNS_IP=$2

### utils function for sending various keys and/or text to the console

function _pressKey() {
  local keyCode=$@

  name=${CLUSTER_NAME}_master_0
  sudo virsh send-key $name $keyCode

  # On some CI instances, the sequence of events appears to be too fast
  # for the console refresh, leading the test in the wrong state.
  # Let's add a small pause between one keypress event and the subsequent
  sleep 1
}

function pressKey() {
  local msg=$1
  local keyCode=$2
  local numReps=1

  if [ ! -z "$3" ]; then
    numReps=$3
    echo "$msg ($numReps)"
  else
    echo $msg
  fi	
  
  for i in $(seq 1 $numReps); do
    _pressKey $keyCode
  done
}

function pressEnter() {
  pressKey "$1" KEY_ENTER "$2"
}

function pressTab() {
  pressKey "$1" KEY_TAB "$2"
}	

function pressDown() {
  pressKey "$1" KEY_DOWN "$2"
}

function pressBackspace() {
  pressKey "$1" KEY_BACKSPACE "$2"
}


function pressEsc() {
  pressKey "$1" KEY_ESC "$2"
}

function pressKeys(){
  local msg=$1
  local text=$2

  echo $msg

  local reNumber='[0-9]'
  local reUpperText='[A-Z]'
  for (( i=0; i<${#text}; i++ )); do
    local c=${text:$i:1}

    if [[ $c =~ ['a-z'] ]]; then
      c=$(echo $c | tr '[:lower:]' '[:upper:]')
    elif [[ $c =~ ['\.'] ]]; then
      c="DOT"
    elif [[ $c =~ [':'] ]]; then
      c="LEFTSHIFT KEY_SEMICOLON"
    fi

    local keyCode="KEY_"$c
    _pressKey $keyCode
  done
}

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
pressDown "Select Quit" 2
pressEnter "Select 'Quit' menu item"
pressEsc "Esc from network tree view"
pressTab "Goto <Quit> button to exit agent-tui" 1

# wait for check to update, to visually see the release image
# check change to passing.
sleep 10
pressEnter "Exit agent-tui"