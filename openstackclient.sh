#!/usr/bin/env bash

set -eu

# shellcheck disable=SC2312
DIR="$(dirname "$(readlink -f "$0")")"
# shellcheck source=common.sh
source "${DIR}/common.sh"

if [[ -d "${PWD}/_clouds_yaml" ]]; then
    MOUNTDIR="${PWD}/_clouds_yaml"
else
    MOUNTDIR="${DIR}/_clouds_yaml"
fi

if [[ "${1:-}" = "baremetal" ]]; then
    shift 1
fi

# shellcheck disable=SC2086
sudo "${CONTAINER_RUNTIME}" run --net=host \
    -v "${MOUNTDIR}:/etc/openstack" --rm \
    -e OS_CLOUD="${OS_CLOUD:-metal3}" "${IRONIC_CLIENT_IMAGE}" "$@"
