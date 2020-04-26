#!/usr/bin/env bash
set -x
set -e

source logging.sh
source utils.sh
source common.sh
source ocp_install_env.sh
source rhcos.sh

verify_pull_secret

# NOTE: This is equivalent to the external API DNS record pointing the API to the API VIP
if [ "$MANAGE_BR_BRIDGE" == "y" ] ; then
    if [[ -n "${EXTERNAL_SUBNET_V6}" ]]; then
        API_VIP=$(dig -t AAAA +noall +answer "api.${CLUSTER_DOMAIN}" @$(network_ip ${BAREMETAL_NETWORK_NAME}) | awk '{print $NF}')
        INGRESS_VIP=$(python -c "from ansible.plugins.filter import ipaddr; print(ipaddr.nthhost('"$EXTERNAL_SUBNET_V6"', 4))")
    else
        API_VIP=$(dig +noall +answer "api.${CLUSTER_DOMAIN}" @$(network_ip ${BAREMETAL_NETWORK_NAME}) | awk '{print $NF}')
        INGRESS_VIP=$(python -c "from ansible.plugins.filter import ipaddr; print(ipaddr.nthhost('"$EXTERNAL_SUBNET_V4"', 4))")
    fi
    echo "address=/api.${CLUSTER_DOMAIN}/${API_VIP}" | sudo tee -a /etc/NetworkManager/dnsmasq.d/openshift-${CLUSTER_NAME}.conf
    echo "address=/.apps.${CLUSTER_DOMAIN}/${INGRESS_VIP}" | sudo tee -a /etc/NetworkManager/dnsmasq.d/openshift-${CLUSTER_NAME}.conf
    echo "listen-address=::1" | sudo tee -a /etc/NetworkManager/dnsmasq.d/openshift-${CLUSTER_NAME}.conf
    sudo systemctl reload NetworkManager
else
    if [[ -n "${EXTERNAL_SUBNET_V6}" ]]; then
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
