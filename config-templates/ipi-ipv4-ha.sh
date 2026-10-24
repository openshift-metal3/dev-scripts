#!/bin/bash
################################################################################
## IPI IPv4 HA Cluster (3 masters, 2 workers)
##
## A full HA IPv4 cluster using traditional IPI (Installer Provisioned
## Infrastructure) with Ironic. Standard deployment with separate control
## plane and worker nodes.
##
## Usage:
##   ./use-template.sh ipi-ipv4-ha
##   # Then edit config_$USER.sh to set your CI_TOKEN
##   make
##
################################################################################

# CI_TOKEN - **REQUIRED**
# Get this token from https://console-openshift-console.apps.ci.l2s4.p1.openshiftapps.com/
# by clicking on your name in the top right corner and copying the login command
set +x
export CI_TOKEN='<insert-your-token-here>'
set -x

# Network: IPv4 single stack (default is v6)
export IP_STACK="v4"
