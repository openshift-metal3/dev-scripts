#!/bin/bash

# source common.sh
set +x

### utils function for sending various keys and/or text to the console

function _pressKey() {
  local keyCode=$1
  local node_name=$2

  # If no node name passed, use default
  if [ -z "$node_name" ]; then
    node_name="${CLUSTER_NAME}_master_0"
  fi
  echo "Sending key to node: $node_name"
  sudo virsh send-key $node_name $keyCode

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
  
  local node_name=$4
  for i in $(seq 1 $numReps); do
    _pressKey $keyCode $node_name
  done
}

function pressEnter() {
  pressKey "$1" KEY_ENTER "$2" "$3"
}

function pressTab() {
  pressKey "$1" KEY_TAB "$2"
}	

function pressDown() {
  pressKey "$1" KEY_DOWN "$2" "$3"
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

function typeIPAddress() {
  local msg=$1
  local ip=$2
  local node=$3
  echo "$msg $ip on node $node"

  for ((i=0; i<${#ip}; i++)); do
    char=${ip:$i:1}

    case "$char" in
      [0-9])
        _pressKey "KEY_$char" $node
        ;;
      ".")
        _pressKey "KEY_DOT" $node
        ;;
      *)
        echo "Unsupported character in IP: $char"
        ;;
    esac
    # mimic a natural typing delay
    sleep 0.1
  done
}

function getRendezvousIP() {
    node_zero_mac_address=$(sudo virsh domiflist ${CLUSTER_NAME}_master_0 | awk '$3 == "ostestbm" {print $5}')
    rendezvousIP=$(ip neigh | grep $node_zero_mac_address | awk '{print $1}')
    echo $rendezvousIP
}