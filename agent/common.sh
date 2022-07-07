#!/usr/bin/env bash
set -euxo pipefail

export AGENT_STATIC_IP_NODE0_ONLY=${AGENT_STATIC_IP_NODE0_ONLY:-"false"}

# Override command name in case of extraction
export OPENSHIFT_INSTALLER_CMD="openshift-install"

if [ -n "$MIRROR_IMAGES" ]; then
    # We're going to be using a locally modified release image
    export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/local-release-image:${OPENSHIFT_RELEASE_TAG}"
fi
