#!/bin/bash
################################################################################
## IPI IPv6 HA Cluster (3 masters, 2 workers)
##
## A full HA IPv6 single-stack cluster using traditional IPI with Ironic.
## Useful for testing IPv6-only environments.
##
## Usage:
##   ./use-template.sh ipi-ipv6-ha
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

# Local registry is required for IPv6 deployments
export ENABLE_LOCAL_REGISTRY=true
