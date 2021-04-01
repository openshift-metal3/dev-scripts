#!/usr/bin/env bash
set -x
set -e

source logging.sh
source common.sh
source network.sh
source utils.sh
source ocp_install_env.sh
source validation.sh

early_deploy_validation

write_pull_secret

# Extract an updated client tools from the release image
extract_oc "${OPENSHIFT_RELEASE_IMAGE}"

mkdir -p $OCP_DIR

save_release_info ${OPENSHIFT_RELEASE_IMAGE} ${OCP_DIR}

if [ -z "$KNI_INSTALL_FROM_GIT" ]; then
  # Extract openshift-install from the release image
  extract_installer "${OPENSHIFT_RELEASE_IMAGE}" $OCP_DIR
  ${OPENSHIFT_INSTALLER} coreos print-stream-json 1>/dev/null 2&1 || extract_rhcos_json "${OPENSHIFT_RELEASE_IMAGE}" $OCP_DIR
else
  # Clone and build the installer from source
  clone_installer
  build_installer
fi
