#!/usr/bin/env bash
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

source $SCRIPTDIR/common.sh
source $SCRIPTDIR/release_info.sh

function validate_installed_manifests() {
    echo "Validating installed operator manifests..."

    # Determine OCP version - manifest validation only supported in 4.21+
    ocp_version=$(openshift_version ${OCP_DIR})
    echo "Detected OpenShift version: ${ocp_version}"

    major_version=$(echo "$ocp_version" | cut -d. -f1)
    minor_version=$(echo "$ocp_version" | cut -d. -f2)

    # Skip validation for versions older than 4.21
    if [ "$major_version" -lt 4 ] || [ "$major_version" -eq 4 -a "$minor_version" -le 20 ]; then
        echo "Manifest validation not supported for version ${ocp_version}, skipping."
        return 0
    fi

    # Suppress trace output for data processing
    set +x

    # Get the ConfigMap as JSON
    if ! configmap_json=$(oc get configmap/olm-operator-manifests -n assisted-installer -o json 2>&1); then
        set -x
        echo "ERROR: Could not find ConfigMap olm-operator-manifests in assisted-installer namespace"
        return 1
    fi

    # Get all keys that end with .metadata.yaml
    metadata_keys=$(echo "$configmap_json" | jq -r '.data | keys[] | select(endswith(".metadata.yaml"))')

    if [ -z "$metadata_keys" ]; then
        set -x
        echo "ERROR: No metadata files found in ConfigMap"
        return 1
    fi

    missing_resources=()

    for metadata_key in $metadata_keys; do
        # Get the metadata content (plain YAML)
        metadata_yaml=$(echo "$configmap_json" | jq -r ".data[\"$metadata_key\"]")

        # Extract manifest filenames (lines starting with "- " in YAML list)
        manifest_files=$(echo "$metadata_yaml" | grep "^- " | sed 's/^- //')

        for manifest_file in $manifest_files; do
            # Get the base64-encoded manifest content and decode it
            manifest_yaml=$(echo "$configmap_json" | jq -r ".data[\"$manifest_file\"]" | base64 -d)

            # Extract kind and name from the manifest YAML
            kind=$(echo "$manifest_yaml" | sed -n 's/^kind: *//p' | head -1 | tr -d '\r')
            name=$(echo "$manifest_yaml" | sed -n 's/^  name: *//p' | head -1 | tr -d '\r')

            if [ -z "$kind" ] || [ -z "$name" ]; then
                set -x
                echo "    WARNING: Could not extract kind or name from $manifest_file"
                set +x
                continue
            fi

            # Try to get resources of this kind
            get_output=$(oc get "$kind" -A --no-headers 2>&1)
            get_exit_code=$?

            if [ $get_exit_code -ne 0 ]; then
                # Check if it's because the resource type doesn't exist
                if echo "$get_output" | grep -q "error: the server doesn't have a resource type"; then
                    missing_resources+=("$kind/$name (resource type '$kind' not available)")
                else
                    # Some other error
                    missing_resources+=("$kind/$name (error: $get_output)")
                fi
            else
                # Resource type exists, check if our specific resource is in the list
                # Check both column 1 (cluster-scoped) and column 2 (namespaced with -A)
                if ! echo "$get_output" | awk '{print $1, $2}' | grep -qw "$name"; then
                    missing_resources+=("$kind/$name")
                fi
            fi
        done
    done

    # Re-enable trace for final output
    set -x

    if [ ${#missing_resources[@]} -gt 0 ]; then
        echo "ERROR: The following expected resources are not applied:"
        for missing_res in "${missing_resources[@]}"; do
            echo "  - $missing_res"
        done
        return 1
    else
        echo "SUCCESS: All expected operator manifests are applied."
    fi
}

function validate_installed_operators() {
    echo "Validating installed operators..."

    # Determine OCP version
    ocp_version=$(openshift_version ${OCP_DIR})

    # Build path to appliance-config.yaml based on version
    APPLIANCE_CONFIG="${SCRIPTDIR}/${OCP_DIR}/iso_builder/src/config/${ocp_version}/appliance-config.yaml"

    if [ ! -f "${APPLIANCE_CONFIG}" ]; then
        echo "ERROR: Could not find appliance-config.yaml at: ${APPLIANCE_CONFIG}"
        return 1
    fi

    echo "Reading operators from: ${APPLIANCE_CONFIG}"

    # Suppress trace output for data processing
    set +x

    # Extract operator names from appliance-config.yaml
    # Look for lines matching "      - name: <operator-name>" under the packages section
    # These are indented with 8 spaces (under operators.packages array)
    expected_operators=()
    while IFS= read -r line; do
        expected_operators+=("$line")
    done < <(grep -A 999 "^operators:" "${APPLIANCE_CONFIG}" | \
             grep "^      - name:" | \
             sed 's/^      - name: *//' | \
             sort)

    if [ ${#expected_operators[@]} -eq 0 ]; then
        set -x
        echo "ERROR: No operators found in ${APPLIANCE_CONFIG}"
        return 1
    fi

    set -x
    echo "Expected operators (${#expected_operators[@]} total):"
    set +x

    for op in "${expected_operators[@]}"; do
        echo "  - $op"
    done

    # Get list of installed operators (just the names, first column)
    installed_operators=$(oc get operators -o custom-columns=NAME:.metadata.name --no-headers)

    missing_operators=()
    for expected_op in "${expected_operators[@]}"; do
        if ! echo "$installed_operators" | grep -q "^${expected_op}\."; then
            missing_operators+=("$expected_op")
        fi
    done

    # Re-enable trace for final output
    set -x

    if [ ${#missing_operators[@]} -gt 0 ]; then
        echo "ERROR: The following expected operators are not installed:"
        for missing_op in "${missing_operators[@]}"; do
            echo "  - $missing_op"
        done
        echo ""
        echo "Installed operators:"
        oc get operators
        return 1
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
    while ! (oc wait clusterversion version --for=condition=Available=True --timeout=2s 2>/dev/null && \
         oc wait clusterversion version --for=condition=Progressing=False --timeout=2s 2>/dev/null); do
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
    validate_installed_operators || exit 1

    # Validate operator manifests are applied
    validate_installed_manifests || exit 1
fi

installed_control_plane_nodes=$(oc get nodes --selector=node-role.kubernetes.io/master | grep -v AGE | wc -l)

oc get nodes

if (( $NUM_MASTERS != $installed_control_plane_nodes )); then
  echo "Post install validation failed. Expected $NUM_MASTERS control plane nodes but found $installed_control_plane_nodes."
  exit 1
fi

oc get clusterversion
