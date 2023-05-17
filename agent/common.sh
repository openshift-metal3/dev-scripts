#!/usr/bin/env bash
set -euxo pipefail

source network.sh

export AGENT_STATIC_IP_NODE0_ONLY=${AGENT_STATIC_IP_NODE0_ONLY:-"false"}

export AGENT_USE_ZTP_MANIFESTS=${AGENT_USE_ZTP_MANIFESTS:-"false"}

# Override command name in case of extraction
export OPENSHIFT_INSTALLER_CMD="openshift-install"

# Override to consistently use the proper subnet
export CLUSTER_HOST_PREFIX_V4="24"
if [[ "$IP_STACK" != "v4" ]]; then
   export EXTERNAL_SUBNET_V6="fd2e:6f44:5dd8:c956::/64"
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

if [[ "$IP_STACK" = "v4v6" ]]; then
    export PROVISIONING_HOST_EXTERNAL_IP_DUALSTACK=$(nth_ip $EXTERNAL_SUBNET_V6 1)
fi
