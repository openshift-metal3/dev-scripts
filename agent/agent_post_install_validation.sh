#!/usr/bin/env bash
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

source $SCRIPTDIR/common.sh
source $SCRIPTDIR/release_info.sh

function validate_installed_operators() {
    echo "Validating installed operators..."

    # Define expected operators per version
    expected_operators_4_20=(
        "cluster-kube-descheduler-operator"
        "fence-agents-remediation"
        "kubernetes-nmstate-operator"
        "kubevirt-hyperconverged"
        "mtv-operator"
        "node-healthcheck-operator"
        "node-maintenance-operator"
    )

    expected_operators_4_21=(
        "cluster-kube-descheduler-operator"
        "cluster-observability-operator"
        "fence-agents-remediation"
        "kubernetes-nmstate-operator"
        "kubevirt-hyperconverged"
        "local-storage-operator"
        "metallb-operator"
        "mtv-operator"
        "node-healthcheck-operator"
        "node-maintenance-operator"
        "numaresources-operator"
        "redhat-oadp-operator"
    )

    # Determine OCP version and select appropriate operator list
    ocp_version=$(openshift_version ${OCP_DIR})
    echo "Detected OpenShift version: ${ocp_version}"

    case "${ocp_version}" in
        "4.20")
            expected_operators=("${expected_operators_4_20[@]}")
            ;;
        "4.21")
            expected_operators=("${expected_operators_4_21[@]}")
            ;;
        *)
            echo "Using 4.21 operator list as default"
            expected_operators=("${expected_operators_4_21[@]}")
            ;;
    esac

    # Get list of installed operators (just the names, first column)
    installed_operators=$(oc get operators -o custom-columns=NAME:.metadata.name --no-headers)

    missing_operators=()
    for expected_op in "${expected_operators[@]}"; do
        if ! echo "$installed_operators" | grep -q "^${expected_op}\."; then
            missing_operators+=("$expected_op")
        fi
    done

    if [ ${#missing_operators[@]} -gt 0 ]; then
        echo "ERROR: The following expected operators are not installed:"
        for missing_op in "${missing_operators[@]}"; do
            echo "  - $missing_op"
        done
        echo ""
        echo "Installed operators:"
        oc get operators
        exit 1
    else
        echo "SUCCESS: All expected operators are installed."
        oc get operators
    fi
}

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

    # Validate expected operators are installed
    validate_installed_operators
fi

installed_control_plane_nodes=$(oc get nodes --selector=node-role.kubernetes.io/master | grep -v AGE | wc -l)

oc get nodes

if (( $NUM_MASTERS != $installed_control_plane_nodes )); then
  echo "Post install validation failed. Expected $NUM_MASTERS control plane nodes but found $installed_control_plane_nodes."
  exit 1
fi

oc get clusterversion
