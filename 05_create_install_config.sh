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

# NOTE: This is equivalent to the external API DNS record pointing the API to the API VIP
if [ "$MANAGE_BR_BRIDGE" == "y" ] ; then
    if [[ -z "${EXTERNAL_SUBNET_V4}" ]]; then
        API_VIP=$(dig -t AAAA +noall +answer "api.${CLUSTER_DOMAIN}" @$(network_ip ${BAREMETAL_NETWORK_NAME}) | awk '{print $NF}')
        INGRESS_VIP=$(nth_ip $EXTERNAL_SUBNET_V6 4)
    else
        API_VIP=$(dig +noall +answer "api.${CLUSTER_DOMAIN}" @$(network_ip ${BAREMETAL_NETWORK_NAME}) | awk '{print $NF}')
        INGRESS_VIP=$(nth_ip $EXTERNAL_SUBNET_V4 4)
    fi
    echo "address=/api.${CLUSTER_DOMAIN}/${API_VIP}" | sudo tee /etc/NetworkManager/dnsmasq.d/openshift-${CLUSTER_NAME}.conf
    echo "address=/.apps.${CLUSTER_DOMAIN}/${INGRESS_VIP}" | sudo tee -a /etc/NetworkManager/dnsmasq.d/openshift-${CLUSTER_NAME}.conf
    echo "listen-address=::1" | sudo tee -a /etc/NetworkManager/dnsmasq.d/openshift-${CLUSTER_NAME}.conf

    # Risk reduction for CVE-2020-25684, CVE-2020-25685, and CVE-2020-25686
    # See: https://access.redhat.com/security/vulnerabilities/RHSB-2021-001
    echo "cache-size=0" | sudo tee -a /etc/NetworkManager/dnsmasq.d/openshift-${CLUSTER_NAME}.conf

    sudo systemctl reload NetworkManager
else
    if [[ -z "${EXTERNAL_SUBNET_V4}" ]]; then
        API_VIP=$(dig -t AAAA +noall +answer "api.${CLUSTER_DOMAIN}"  | awk '{print $NF}')
    else
        API_VIP=$(dig +noall +answer "api.${CLUSTER_DOMAIN}"  | awk '{print $NF}')
    fi
    INGRESS_VIP=$(dig +noall +answer "test.apps.${CLUSTER_DOMAIN}" | awk '{print $NF}')
fi

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
    generate_extra_host_manifest ${OCP_DIR} ${EXTRA_BAREMETALHOSTS_FILE} extra_host_manifests.yaml openshift-machine-api
fi
