#!/usr/bin/env bash
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR=${SCRIPTDIR}/logs
source $SCRIPTDIR/logging.sh
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/agent/common.sh

# Use the development branch for building the openshift installer.
# Used only when KNI_INSTALL_FROM_GIT is set and OPENSHIFT_INSTALL_PATH
# does not exists. This setting will be removed once the development
# branch will be merged in the installer main
export INSTALLER_REPO_BRANCH=agent-installer

# Override build tags
export OPENSHIFT_INSTALLER_BUILD_TAGS=" "

# Override command name in case of extraction
export OPENSHIFT_INSTALLER_CMD="openshift-install"

source $SCRIPTDIR/03_build_installer.sh

# Copy install binary if built from src
if [ ! -z "$KNI_INSTALL_FROM_GIT" -a -f "$OPENSHIFT_INSTALL_PATH/bin/openshift-install" ]; then 
    cp "$OPENSHIFT_INSTALL_PATH/bin/openshift-install" "$OCP_DIR"
fi
