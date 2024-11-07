#!/usr/bin/env bash
set -x
set -e

source logging.sh
source common.sh
source network.sh
source utils.sh
source ocp_install_env.sh
source rhcos.sh
source validation.sh

early_deploy_validation

set_api_and_ingress_vip

if [ ! -f ${OCP_DIR}/install-config.yaml ]; then
    # Validate there are enough nodes to avoid confusing errors later..
    NODES_LEN=$(jq '.nodes | length' ${NODES_FILE})
    if (( $NODES_LEN < ( $NUM_MASTERS + $NUM_WORKERS ) )); then
        echo "ERROR: ${NODES_FILE} contains ${NODES_LEN} nodes, but ${NUM_MASTERS} masters and ${NUM_WORKERS} workers requested"
        exit 1
    fi

    # Create a nodes.json file
    mkdir -p ${OCP_DIR}
    jq '{nodes: .}' "${NODES_FILE}" | tee "${BAREMETALHOSTS_FILE}"

    # Create install config for openshift-installer
    generate_ocp_install_config ${OCP_DIR}
fi

# Generate the assets for extra worker VMs
if [ -f "${EXTRA_NODES_FILE}" ]; then
    jq '.nodes' "${EXTRA_NODES_FILE}" | tee "${EXTRA_BAREMETALHOSTS_FILE}"
    generate_ocp_host_manifest ${OCP_DIR} ${EXTRA_BAREMETALHOSTS_FILE} extra_host_manifests.yaml ${EXTRA_WORKERS_NAMESPACE}
fi
