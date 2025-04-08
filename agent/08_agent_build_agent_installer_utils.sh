#!/usr/bin/env bash
set -x
set -e

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR=${SCRIPTDIR}/logs
source $SCRIPTDIR/logging.sh
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
  ./hack/build-ove-image.sh --pull-secret-file "${PULL_SECRET_FILE}" --release-image-url "${OPENSHIFT_RELEASE_IMAGE}" 
  # --dir "${OCP_DIR}" #Error: creating named volume "ocp/ostest/appliance-assets-4.19.0-0.ci-2025-04-04-173808/": running volume create option: names must match [a-zA-Z0-9][a-zA-Z0-9_.-]*: invalid argument
  popd
}

early_deploy_validation

write_pull_secret

# Extract an updated client tools from the release image
extract_oc "${OPENSHIFT_RELEASE_IMAGE}"

clone_agent_installer_utils
build_agent_ove_image
