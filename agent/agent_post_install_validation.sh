#!/usr/bin/env bash
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

source $SCRIPTDIR/common.sh

# Temp code skip the execution flow as cluster is not really installed
if [[ "${AGENT_E2E_TEST_BOOT_MODE}" == "ISO_NO_REGISTRY" ]]; then
  exit 0
fi

installed_control_plane_nodes=$(oc get nodes --selector=node-role.kubernetes.io/master | grep -v AGE | wc -l)

oc get nodes

if (( $NUM_MASTERS != $installed_control_plane_nodes )); then
  echo "Post install validation failed. Expected $NUM_MASTERS control plane nodes but found $installed_control_plane_nodes."
  exit 1
fi
