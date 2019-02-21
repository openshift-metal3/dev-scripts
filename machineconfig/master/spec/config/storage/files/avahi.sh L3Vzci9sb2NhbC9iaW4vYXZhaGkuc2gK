#!/usr/bin/env bash
set -e

mkdir --parents /etc/avahi
SHORT_HOSTNAME="$(hostname -s)" envsubst < /etc/avahi/avahi-daemon.conf.template > /etc/avahi/avahi-daemon.conf

AVAHI_IMAGE=quay.io/celebdor/avahi:f29
if ! podman inspect "$AVAHI_IMAGE" &>/dev/null; then
    (>&2 echo "Pulling avahi release image...")
    podman pull "$AVAHI_IMAGE"
fi

podman run \
        --rm \
        --volume /etc/avahi:/etc/avahi:z \
        --network=host \
        "${AVAHI_IMAGE}"

# Workaround for https://github.com/opencontainers/runc/pull/1807
touch /etc/avahi/.avahi.done

