#!/bin/bash
################################################################################
## Agent-Based SNO IPv6 (Single Node OpenShift)
##
## A single-node OpenShift deployment using the agent-based installer with
## IPv6 networking. For edge scenarios requiring IPv6-only connectivity.
##
## Usage:
##   ./use-template.sh agent-sno-ipv6
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

# Agent-based installer settings
export AGENT_E2E_TEST_SCENARIO="SNO_IPV6"

# Local registry is required for IPv6 deployments
export ENABLE_LOCAL_REGISTRY=true
