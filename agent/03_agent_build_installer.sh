#!/usr/bin/env bash
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR=${SCRIPTDIR}/logs
source $SCRIPTDIR/logging.sh
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/ocp_install_env.sh
source $SCRIPTDIR/agent/common.sh

# Override build tags
export OPENSHIFT_INSTALLER_BUILD_TAGS=" "

source $SCRIPTDIR/03_build_installer.sh

# Writes the currently used openshift version in the installer binary,
# if it was built from src
function patch_openshift_install_version() {
    local res=$(grep -oba ._RELEASE_VERSION_LOCATION_.XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX ${OCP_DIR}/openshift-install)
    local location=${res%%:*}

    # If the release marker was found then it means that the version is missing
    if [[ ! -z ${location} ]]; then
        version="$(openshift_release_version ${OCP_DIR})"
        echo "Patching openshift-install with version ${version}"
        printf "${version}\0" | dd of=${OCP_DIR}/openshift-install bs=1 seek=${location} conv=notrunc &> /dev/null 
    fi
}

# Copy install binary if built from src
if [ ! -z "$KNI_INSTALL_FROM_GIT" -a -f "$OPENSHIFT_INSTALL_PATH/bin/openshift-install" ]; then
    cp "$OPENSHIFT_INSTALL_PATH/bin/openshift-install" "$OCP_DIR"

    patch_openshift_install_version
fi
