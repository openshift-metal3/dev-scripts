#!/usr/bin/env bash

set -x
set -e

source logging.sh
source utils.sh
source common.sh
if [ "$NODES_PLATFORM" = "assisted" ]; then
  exit 0
fi


source ocp_install_env.sh

# Extract an updated client tools from the release image
extract_oc "${OPENSHIFT_RELEASE_IMAGE}"

mkdir -p $OCP_DIR

if [ -z "$KNI_INSTALL_FROM_GIT" ]; then
  # Extract openshift-install from the release image
  extract_installer "${OPENSHIFT_RELEASE_IMAGE}" $OCP_DIR
  extract_rhcos_json "${OPENSHIFT_RELEASE_IMAGE}" $OCP_DIR
else
  # Clone and build the installer from source
  clone_installer
  build_installer
fi
