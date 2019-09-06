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
    API_VIP=$(dig +noall +answer "api.${CLUSTER_DOMAIN}" @$(network_ip baremetal) | awk '{print $NF}')
    INGRESS_VIP=$(python -c "from ansible.plugins.filter import ipaddr; print(ipaddr.nthhost('"$EXTERNAL_SUBNET"', 4))")
    echo "address=/api.${CLUSTER_DOMAIN}/${API_VIP}" | sudo tee /etc/NetworkManager/dnsmasq.d/openshift.conf
    echo "address=/.apps.${CLUSTER_DOMAIN}/${INGRESS_VIP}" | sudo tee -a /etc/NetworkManager/dnsmasq.d/openshift.conf
    sudo systemctl reload NetworkManager
else
    API_VIP=$(dig +noall +answer "api.${CLUSTER_DOMAIN}"  | awk '{print $NF}')
    INGRESS_VIP=$(dig +noall +answer "test.apps.${CLUSTER_DOMAIN}" | awk '{print $NF}')
fi

# Override release images with ones built from our local git repos if the
# configuration calls for it.
IMAGE_OVERRIDES=""
if [ -n "$COREDNS_IMAGE" ]; then
    # TODO: Figure out how to include coredns-mdns changes in this build
    # It requires modification of a coredns file, like:
    # echo "replace github.com/openshift/coredns-mdns => $source_dir" >> "$GOPATH/src/github.com/coredns/coredns/go.mod"
    pushd "$COREDNS_IMAGE"
    coredns_id=$(sudo buildah bud -f Dockerfile.openshift . | tail -n 1)
    sudo podman tag $coredns_id quay.io/cybertron/coredns
    sudo podman push quay.io/cybertron/coredns
    IMAGE_OVERRIDES="$IMAGE_OVERRIDES coredns=quay.io/cybertron/coredns:latest"
    popd
fi
if [ -n "$BAREMETAL_RUNTIMECFG_IMAGE" ]; then
    pushd "$BAREMETAL_RUNTIMECFG_IMAGE"
    baremetal_runtimecfg_id=$(sudo buildah bud -f Dockerfile . | tail -n 1)
    sudo podman tag $baremetal_runtimecfg_id quay.io/cybertron/baremetal-runtimecfg
    sudo podman push quay.io/cybertron/baremetal-runtimecfg
    IMAGE_OVERRIDES="$IMAGE_OVERRIDES baremetal-runtimecfg=quay.io/cybertron/baremetal-runtimecfg:latest"
    popd
fi
# TODO: Build mdns-publisher

# Build a new release, based on the configured release, that overrides the
# appropriate images built above.
if [ -n "$IMAGE_OVERRIDES" ]; then
    # This is what I would like to do, but it doesn't work
#     oc adm release new -n ocp \
#         --server https://api.ci.openshift.org \
#         --from-release "$OPENSHIFT_RELEASE_IMAGE" \
#         --to-image quay.io/cybertron/origin-release:v4.2 \
#         $IMAGE_OVERRIDES || :
    # This works in isolation but not when run as part of this script. :-/
    oc adm release new -n ocp \
        --server https://api.ci.openshift.org \
        --from-image-stream "4.2-art-latest" \
        --to-image quay.io/cybertron/origin-release:v4.2 \
        $IMAGE_OVERRIDES || :
    OPENSHIFT_RELEASE_IMAGE="quay.io/cybertron/origin-release:v4.2"
fi

if [ ! -f ocp/install-config.yaml ]; then
    # Validate there are enough nodes to avoid confusing errors later..
    NODES_LEN=$(jq '.nodes | length' ${NODES_FILE})
    if (( $NODES_LEN < ( $NUM_MASTERS + $NUM_WORKERS ) )); then
        echo "ERROR: ${NODES_FILE} contains ${NODES_LEN} nodes, but ${NUM_MASTERS} masters and ${NUM_WORKERS} workers requested"
        exit 1
    fi

    # Create a master_nodes.json file
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
