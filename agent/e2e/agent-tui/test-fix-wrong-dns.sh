#!/bin/bash

### utils function for sending various keys and/or text to the console

function _pressKey() {
  local keyCode=$1

  sudo virsh send-key ostest_master_0 "$keyCode" 
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
    fi

    local keyCode="KEY_"$c
    _pressKey $keyCode
  done
}

### Setup: create an agent ISO using an incorrect DNS address in the agent-config.yaml

pressEnter "Select '<Configure network>' button"
pressEnter "Select 'Edit a connection'"
pressEnter "Select 'enp2s0'"
pressTab "Goto DNS field" 9
pressBackspace "Cleanup DNS previous value" 15
pressKeys "Insert correct DNS address" "192.168.111.1"


