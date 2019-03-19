#!/usr/bin/env bash
set -e

mkdir --parents /etc/mdns

CLUSTER_DOMAIN="$(awk '/search/ {print $2}' /etc/resolv.conf)"
API_VIP="$(dig +noall +answer "api.${CLUSTER_DOMAIN}" | awk '{print $NF}')"
IFACE_CIDRS="$(ip addr show | grep -v "scope host" | grep -Po 'inet \K[\d.]+/[\d.]+' | xargs)"
SUBNET_CIDR="$(/usr/local/bin/get_vip_subnet_cidr "$API_VIP" "$IFACE_CIDRS")"
PREFIX="${SUBNET_CIDR#*/}"
DNS_VIP="$(/usr/local/bin/nthhost "$SUBNET_CIDR" 2)"
ONE_CIDR="$(ip addr show to "$SUBNET_CIDR" | \
            grep -Po 'inet \K[\d.]+/[\d.]+' | \
            grep -v "${DNS_VIP}/$PREFIX" | \
            grep -v "${API_VIP}/$PREFIX" | \
            sort | xargs | cut -f1 -d' ')"

NON_VIRTUAL_IP="${ONE_CIDR%/*}"
MASTER_HOSTNAME="$(hostname -s).local."
ETCD_HOSTNAME="$(echo "$MASTER_HOSTNAME" | sed 's;master;etcd;')"
export MASTER_HOSTNAME
export ETCD_HOSTNAME
export NON_VIRTUAL_IP
envsubst < /etc/mdns/config.template | sudo tee /etc/mdns/config.hcl

MDNS_PUBLISHER_IMAGE="quay.io/openshift-metalkube/mdns-publisher:collision_avoidance"
if ! podman inspect "$MDNS_PUBLISHER_IMAGE" &>/dev/null; then
    (>&2 echo "Pulling mdns-publisher release image...")
    podman pull "$MDNS_PUBLISHER_IMAGE"
fi

# Check if the pod exists
MATCHES="$(sudo podman ps -a --format "{{.Names}}" | awk '/mdns-publisher$/ {print $0}')"
if [[ -z "$MATCHES" ]]; then
    podman create \
        --net host \
        --name mdns-publisher \
        --volume /etc/mdns:/etc/mdns:z \
        "$MDNS_PUBLISHER_IMAGE" \
            --debug
fi
