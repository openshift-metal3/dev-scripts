#!/usr/bin/env bash
set -e

mkdir --parents /etc/coredns

CLUSTER_DOMAIN="$(/usr/local/bin/clusterinfo DOMAIN)"
CLUSTER_NAME="$(/usr/local/bin/clusterinfo NAME)"
DNS_VIP="$(dig +noall +answer "ns1.${CLUSTER_DOMAIN}" | awk '{print $NF}')"
grep -v "${DNS_VIP}" /etc/resolv.conf | tee /etc/coredns/resolv.conf

COREDNS_IMAGE="quay.io/openshift-metalkube/coredns-mdns:latest"
if ! podman inspect "$COREDNS_IMAGE" &>/dev/null; then
    echo "Pulling release image..."
    podman pull "$COREDNS_IMAGE"
fi
MATCHES="$(sudo podman ps -a --format "{{.Names}}" | awk '/coredns$/ {print $0}')"
if [[ -z "$MATCHES" ]]; then
    /usr/bin/podman create \
        --name coredns \
        --volume /etc/coredns:/etc/coredns:z \
        --network host \
        --env CLUSTER_DOMAIN="$CLUSTER_DOMAIN" \
        --env CLUSTER_NAME="$CLUSTER_NAME" \
        "${COREDNS_IMAGE}" \
            --conf /etc/coredns/Corefile
fi
