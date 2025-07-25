#!/bin/bash

set +x

### utils function for sending various keys and/or text to the console

function _pressKey() {
  local keyCode=$1
  local node_name=$2

  # If no node name passed, use default
  if [ -z "$node_name" ]; then
    node_name="${CLUSTER_NAME}_master_0"
  fi
  sudo virsh send-key $node_name $keyCode

  timestamp=$(date +"%Y-%m-%d--%H:%M:%S")
  sudo virsh screenshot $node_name "${OCP_DIR}/${timestamp}-${node_name}_after_${keyCode}.ppm"

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
  local node=$3

  if [[ -n "$node" ]]; then
    echo "$msg $text on node $node"
  else
   echo $msg
  fi

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
    _pressKey $keyCode $node
  done
}
