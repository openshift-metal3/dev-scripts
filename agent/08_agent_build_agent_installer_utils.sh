#!/usr/bin/env bash
set -x
set -e

source common.sh
source utils.sh
source ocp_install_env.sh
source validation.sh

function clone_agent_installer_utils() {
  # Clone repo, if not already present
  if [[ ! -d $OPENSHIFT_AGENT_INSTALER_UTILS_PATH ]]; then
    sync_repo_and_patch go/src/github.com/openshift/agent-installer-utils https://github.com/openshift/agent-installer-utils.git
  fi
}

function build_agent_ove_image() {
  # Build installer
  pushd .
  cd $OPENSHIFT_AGENT_INSTALER_UTILS_PATH/tools/iso_builder
  OCP_RELEASE_IMAGE="${OPENSHIFT_RELEASE_IMAGE}" PULL_SECRET="${PULL_SECRET_FILE}" ARCH=$(get_arch) make build-ove-iso
  popd
}

early_deploy_validation

write_pull_secret

# Extract an updated client tools from the release image
extract_oc "${OPENSHIFT_RELEASE_IMAGE}"

clone_agent_installer_utils
build_agent_ove_image
