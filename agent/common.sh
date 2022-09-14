#!/usr/bin/env bash
set -euxo pipefail

export AGENT_STATIC_IP_NODE0_ONLY=${AGENT_STATIC_IP_NODE0_ONLY:-"false"}

# Override command name in case of extraction
export OPENSHIFT_INSTALLER_CMD="openshift-install"

if [ -n "$MIRROR_IMAGES" ]; then
    # We're going to be using a locally modified release image
    export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/local-release-image:${OPENSHIFT_RELEASE_TAG}"
fi

function getReleaseImage() {
    local releaseImage=${OPENSHIFT_RELEASE_IMAGE}
    if [ ! -z "${MIRROR_IMAGES}" ]; then
        releaseImage="${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}"
    # If not installing from src, let's use the current version from the binary
    elif [ -z "$KNI_INSTALL_FROM_GIT" ]; then
      local openshift_install="$(realpath "${OCP_DIR}/openshift-install")"
      releaseImage=$("${openshift_install}" --dir="${OCP_DIR}" version | grep "release image" | cut -d " " -f 3)      
    fi
    echo ${releaseImage}
}