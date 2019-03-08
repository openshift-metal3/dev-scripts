#!/usr/bin/env bash
set -e

mkdir --parents /etc/keepalived

CLUSTER_DOMAIN="$(awk '/search/ {print $2}' /etc/resolv.conf)"
API_VIP="$(dig +noall +answer "api.${CLUSTER_DOMAIN}" | awk '{print $NF}')"
IFACE_CIDRS="$(ip addr show | grep -v "scope host" | grep -Po 'inet \K[\d.]+/[\d.]+' | xargs)"
SUBNET_CIDR="$(/usr/local/bin/get_vip_subnet_cidr "$API_VIP" "$IFACE_CIDRS")"
INTERFACE="$(ip -o addr show to "$SUBNET_CIDR" | awk '{print $2}')"


KEEPALIVED_IMAGE="quay.io/celebdor/keepalived:latest"
if ! podman inspect "$KEEPALIVED_IMAGE" &>/dev/null; then
    echo "Pulling release image..."
    podman pull "$KEEPALIVED_IMAGE"
fi

export API_VIP
export INTERFACE
envsubst < /etc/keepalived/keepalived.conf.template | sudo tee /etc/keepalived/keepalived.conf

MATCHES="$(sudo podman ps -a --format "{{.Names}}" | awk '/keepalived$/ {print $0}')"
if [[ -z "$MATCHES" ]]; then
    podman create \
        --name keepalived \
        --volume /etc/keepalived:/etc/keepalived:z \
        --network=host \
        --cap-add=NET_ADMIN \
        "${KEEPALIVED_IMAGE}" \
            /usr/sbin/keepalived -f /etc/keepalived/keepalived.conf \
                --dont-fork -D -l -P
fi
