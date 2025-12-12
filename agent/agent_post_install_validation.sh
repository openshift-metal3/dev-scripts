#!/usr/bin/env bash
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

source $SCRIPTDIR/common.sh

if [[ "${AGENT_E2E_TEST_BOOT_MODE}" == "ISO_NO_REGISTRY" ]]; then
    MAX_ATTEMPTS=120
    SLEEP_SECONDS=30  # Wait time between connection attempts
    ATTEMPT_COUNT=0

    echo "Starting oc wait retry loop for API connection up to 60 minutes..."
    set +x  # Disable debug tracing for cleaner output
    while ! oc wait clusterversion version --for=condition=Available=True --timeout=1s 2>/dev/null; do
        ATTEMPT_COUNT=$((ATTEMPT_COUNT + 1))
        if [ $ATTEMPT_COUNT -ge $MAX_ATTEMPTS ]; then
            echo ""
            set -x  # Re-enable debug tracing
            echo "ERROR: API server connection failed after $MAX_ATTEMPTS attempts over 60 minutes."
            exit 1
        fi

        echo -n "."
        sleep $SLEEP_SECONDS
    done
    echo ""
    set -x  # Re-enable debug tracing
    echo "SUCCESS: API server connection established and ClusterVersion is available."
    # Run subsequent commands after successful cluster setup
    oc get packagemanifests -n openshift-marketplace
fi

installed_control_plane_nodes=$(oc get nodes --selector=node-role.kubernetes.io/master | grep -v AGE | wc -l)

oc get nodes

if (( $NUM_MASTERS != $installed_control_plane_nodes )); then
  echo "Post install validation failed. Expected $NUM_MASTERS control plane nodes but found $installed_control_plane_nodes."
  exit 1
fi

oc get clusterversion
