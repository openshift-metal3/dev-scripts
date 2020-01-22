#!/usr/bin/env bash
set -x
set -e

source logging.sh
source utils.sh
source common.sh
source ocp_install_env.sh
source rhcos.sh

# Do some PULL_SECRET sanity checking
if [[ "${OPENSHIFT_RELEASE_IMAGE}" == *"registry.svc.ci.openshift.org"* ]]; then
    if [[ "${PULL_SECRET}" != *"registry.svc.ci.openshift.org"* ]]; then
        echo "Please get a valid pull secret for registry.svc.ci.openshift.org."
        exit 1
    fi
fi

if [[ "${PULL_SECRET}" != *"cloud.openshift.com"* ]]; then
    echo "Please get a valid pull secret for cloud.openshift.com."
    exit 1
fi

# NOTE: This is equivalent to the external API DNS record pointing the API to the API VIP
if [ "$MANAGE_BR_BRIDGE" == "y" ] ; then
    if [[ $EXTERNAL_SUBNET =~ .*:.* ]]; then
        API_VIP=$(dig -t AAAA +noall +answer "api.${CLUSTER_DOMAIN}" @$(network_ip baremetal) | awk '{print $NF}')
    else
        API_VIP=$(dig +noall +answer "api.${CLUSTER_DOMAIN}" @$(network_ip baremetal) | awk '{print $NF}')
    fi
    INGRESS_VIP=$(python -c "from ansible.plugins.filter import ipaddr; print(ipaddr.nthhost('"$EXTERNAL_SUBNET"', 4))")
    echo "address=/api.${CLUSTER_DOMAIN}/${API_VIP}" | sudo tee -a /etc/NetworkManager/dnsmasq.d/openshift.conf
    echo "address=/.apps.${CLUSTER_DOMAIN}/${INGRESS_VIP}" | sudo tee -a /etc/NetworkManager/dnsmasq.d/openshift.conf
    echo "listen-address=::1" | sudo tee -a /etc/NetworkManager/dnsmasq.d/openshift.conf
    sudo systemctl reload NetworkManager
else
    if [[ $EXTERNAL_SUBNET =~ .*:.* ]]; then
        API_VIP=$(dig -t AAAA +noall +answer "api.${CLUSTER_DOMAIN}"  | awk '{print $NF}')
    else
        API_VIP=$(dig +noall +answer "api.${CLUSTER_DOMAIN}"  | awk '{print $NF}')
    fi
    INGRESS_VIP=$(dig +noall +answer "test.apps.${CLUSTER_DOMAIN}" | awk '{print $NF}')
fi

if [ ! -f ocp/install-config.yaml ]; then
    # Validate there are enough nodes to avoid confusing errors later..
    NODES_LEN=$(jq '.nodes | length' ${NODES_FILE})
    if (( $NODES_LEN < ( $NUM_MASTERS + $NUM_WORKERS ) )); then
        echo "ERROR: ${NODES_FILE} contains ${NODES_LEN} nodes, but ${NUM_MASTERS} masters and ${NUM_WORKERS} workers requested"
        exit 1
    fi

    # Create a master_nodes.json file
    mkdir -p ocp/
    jq '.nodes[0:3] | {nodes: .}' "${NODES_FILE}" | tee "${MASTER_NODES_FILE}"

    # Create install config for openshift-installer
    generate_ocp_install_config ocp
fi

# Call openshift-installer to deploy the bootstrap node and masters
create_cluster ocp

# Kill the dnsmasq container on the host since it is performing DHCP and doesn't
# allow our pod in openshift to take over.  We don't want to take down all of ironic
# as it makes cleanup "make clean" not work properly.
for name in dnsmasq ironic-inspector ; do
    sudo podman ps | grep -w "$name$" && sudo podman stop $name
done

echo "Cluster up, you can interact with it via oc --config ${KUBECONFIG} <command>"
