#!/usr/bin/env bash
set -x
set -e

source logging.sh
source utils.sh
source common.sh
source ocp_install_env.sh

# Extract an updated client tools from the release image
extract_oc "${OPENSHIFT_RELEASE_IMAGE}"

mkdir -p ocp/

if [ -z "$KNI_INSTALL_FROM_GIT" ]; then
  # Extract openshift-install from the release image
  extract_installer "${OPENSHIFT_RELEASE_IMAGE}" ocp/
else
  # Clone and build the installer from source
  clone_installer
  build_installer
fi
