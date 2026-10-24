#!/bin/bash
################################################################################
## Agent-Based HA IPv4 (3 masters, 2 workers)
##
## A full HA cluster using the agent-based installer with IPv4 networking.
## Standard production-like topology with separate control plane and workers.
##
## Usage:
##   ./use-template.sh agent-ha-ipv4
##   # Then edit config_$USER.sh to set your CI_TOKEN
##   cd agent && ./01_agent_requirements.sh && ./03_agent_build_installer.sh && \
##     ./04_agent_prepare_release.sh && ./05_agent_configure.sh && \
##     ./06_agent_create_cluster.sh
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

# Agent-based installer settings
export AGENT_E2E_TEST_SCENARIO="HA_IPV4"
