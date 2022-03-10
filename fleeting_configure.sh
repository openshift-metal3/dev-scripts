#!/bin/bash

# FIXME(lranjbar): Replace with Ansible role to define configuration for Multi/Compact/SNO
source config_example_compact.sh

# USAGE: Update this variable to where your fleeting directory is here or on the command line
#export FLEETING_REPO_DIR=${$FLEETING_REPO_DIR:-$HOME/github/openshift-agent-team/fleeting/}
export FLEETING_REPO_DIR=${$FLEETING_REPO_DIR}

# Sets the default locations of the ISO built by fleeting
export FLEETING_ISO_NAME=${FLEETING_ISO_NAME:-fleeting.iso}
export FLEETING_ISO_LOCATION=${FLEETING_ISO_LOCATION:-$FLEETING_REPO_DIR/$FLEETING_ISO_NAME}

# Sets the configuration for the fleeting VM
export NUM_FLEETINGS=1
export FLEETING_MEMORY=8192
export FLEETING_DISK=20
export FLEETING_VCPU=4