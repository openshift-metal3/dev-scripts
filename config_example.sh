#!/bin/bash

# Get a valid pull secret (json string) from
# You can get this secret from https://cloud.openshift.com/clusters/install#pull-secret
set +x
export PULL_SECRET=''
set -x

# Uncomment to build a copy of ironic or inspector locally
#export IRONIC_INSPECTOR_IMAGE=https://github.com/metal3-io/ironic-inspector
#export IRONIC_IMAGE=https://github.com/metal3-io/ironic

# SSH key used to ssh into deployed hosts.  This must be the contents of the
# variable, not the filename. The contents of ~/.ssh/id_rsa.pub are used by
# default.
#export SSH_PUB_KEY=$(cat ~/.ssh/id_rsa.pub)

# Configure custom ntp servers if needed
#export NTP_SERVERS="00.my.internal.ntp.server.com;01.other.ntp.server.com"

# Indicate number of workers to deploy
#export NUM_WORKERS=0

# Provisioning interface on the helper ndoe
#export PRO_IF="eno1"

# Internal interface
#export INT_IF="eno2"

# Provisioning interface within the cluster
#export CLUSTER_PRO_IF="eno1"

# Which disk to deploy 
#export ROOT_DISK="/dev/sda"

# Cluster name
#export CLUSTER_NAME="mycluster"

# Domain name
#export BASE_DOMAIN="kni.lab.metal3.io"

# Manage bridge
#export MANAGE_BR_BRIDGE=n

# Path to the json files with ipmi credentials
#export NODES_FILE="/root/git/dev-scripts/bm.json"

# Whether the installation is on baremetal or not
#export NODES_PLATFORM=BM

# DNS_VIP
#export DNS_VIP="11.0.0.2"

# External subnet
#export EXTERNAL_SUBNET="11.0.0.0/24"
