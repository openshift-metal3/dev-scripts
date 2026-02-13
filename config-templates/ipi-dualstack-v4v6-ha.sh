#!/bin/bash
################################################################################
## IPI Dual-Stack HA Cluster (IPv4-primary, 3 masters, 2 workers)
##
## A dual-stack cluster using traditional IPI with Ironic.
## IPv4-primary with IPv6 secondary.
##
## Usage:
##   ./use-template.sh ipi-dualstack-v4v6-ha
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

# Network: IPv4-primary dual stack
export IP_STACK="v4v6"

# Local registry is required for dual-stack deployments
export ENABLE_LOCAL_REGISTRY=true
