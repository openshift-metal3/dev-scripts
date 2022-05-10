#!/usr/bin/env bash
set -euxo pipefail

DEVSCRIPTS_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR=${DEVSCRIPTS_SCRIPT_DIR}/logs
source $DEVSCRIPTS_SCRIPT_DIR/logging.sh
source $SCRIDEVSCRIPTS_SCRIPT_DIRPTDIR/common.sh
source $DEVSCRIPTS_SCRIPT_DIR/agent/common.sh

# Use the development branch for building the openshift installer.
# Used only when KNI_INSTALL_FROM_GIT is set and OPENSHIFT_INSTALL_PATH
# does not exists. This setting will be removed once the development
# branch will be merged in the installer main
export INSTALLER_REPO_BRANCH=agent-installer

# Override build tags
export OPENSHIFT_INSTALLER_BUILD_TAGS=" "

# Override command name in case of extraction
export OPENSHIFT_INSTALLER_CMD="openshift-install"

source $DEVSCRIPTS_SCRIPT_DIR/03_build_installer.sh

# Copy install binary if built from src
if [ ! -z "$KNI_INSTALL_FROM_GIT" -a -f "$OPENSHIFT_INSTALL_PATH/bin/openshift-install" ]; then
    cp "$OPENSHIFT_INSTALL_PATH/bin/openshift-install" "$OCP_DIR"
fi