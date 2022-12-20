#!/usr/bin/env bash
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR=${SCRIPTDIR}/logs
source $SCRIPTDIR/logging.sh
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/network.sh
source $SCRIPTDIR/utils.sh
source $SCRIPTDIR/validation.sh
source $SCRIPTDIR/agent/common.sh
source $SCRIPTDIR/ocp_install_env.sh
source $SCRIPTDIR/oc_mirror.sh

# To replace an image entry in the openshift release image, set <ENTRYNAME>_LOCAL_REPO so that:
# - ENTRYNAME matches an uppercase version of the name in the release image with "-" converted to "_" 
# - The var value must point to an already locally cloned repo
#
# To specify a custom Dockerfile set <ENTRYNAME>_DOCKERFILE, as a relative path of the Dockerfile
# within the configured repo
#
# For example, to use a custom installer image:
# export INSTALLER_LOCAL_REPO=~/go/src/github.com/openshift/installer
# export INSTALLER_DOCKERFILE=images/installer/Dockerfile.ci

early_deploy_validation
write_pull_secret

# Release mirroring could be required by the subsequent steps
# even if the current one will be skipped
if [[ ! -z "${MIRROR_IMAGES}" ]]; then
   setup_release_mirror
fi

function build_local_release() {
    # Sanity checks
    if [ -z "${MIRROR_IMAGES}" ] ; then 
        echo "Please set MIRROR_IMAGES to rebuild a local release"
        exit 1
    fi

    if [[ ! "$OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE" =~ "$LOCAL_REGISTRY_DNS_NAME" ]] ; then
        echo "OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE mismatch, it must reference the local registry"
        exit 1
    fi

    # Prepare new release
    DOCKERFILE=$(mktemp --tmpdir "release-update--XXXXXXXXXX")
    _tmpfiles="$_tmpfiles $DOCKERFILE"
    echo "FROM $OPENSHIFT_RELEASE_IMAGE" > $DOCKERFILE

    # Build new images
    for IMAGE_VAR in $REPO_OVERRIDES ; do
        
        if [[ ! -d ${!IMAGE_VAR} ]]; then
            echo "The specified local repo ${IMAGE_VAR}=${!IMAGE_VAR} does not exist"
            exit 1
        fi
        cd ${!IMAGE_VAR}
        
        export $IMAGE_VAR=${!IMAGE_VAR##*/}:latest
        export $IMAGE_VAR=$LOCAL_REGISTRY_DNS_NAME:$LOCAL_REGISTRY_PORT/localimages/${!IMAGE_VAR}

        # Some repos need to build with a non-default Dockerfile name
        IMAGE_DOCKERFILE_NAME=${IMAGE_VAR/_LOCAL_REPO}_DOCKERFILE
        IMAGE_DOCKERFILE=${!IMAGE_DOCKERFILE_NAME:-}
        if [[ -z "$IMAGE_DOCKERFILE" ]]; then
            for IMAGE_DOCKERFILE in Dockerfile.ocp Dockerfile; do
                if [[ -e "$IMAGE_DOCKERFILE" ]]; then
                    break
                fi
            done
        fi

        sudo podman build --network host --authfile $PULL_SECRET_FILE -t ${!IMAGE_VAR} -f $IMAGE_DOCKERFILE .
        cd -
        sudo podman push --tls-verify=false --authfile $PULL_SECRET_FILE ${!IMAGE_VAR} ${!IMAGE_VAR}
        
        IMAGE_NAME=$(echo ${IMAGE_VAR/_LOCAL_REPO} | tr '[:upper:]_' '[:lower:]-')
        OLDIMAGE=$(sudo podman run --rm --authfile $PULL_SECRET_FILE $OPENSHIFT_RELEASE_IMAGE image $IMAGE_NAME)
        echo "RUN sed -i 's%$OLDIMAGE%${!IMAGE_VAR}%g' /release-manifests/*" >> $DOCKERFILE
    done

    # Publish the new release in the local registry
    if [ ! -z "${MIRROR_IMAGES}" ]; then        
        sudo podman image build --authfile $PULL_SECRET_FILE -t $OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE -f $DOCKERFILE
        sudo podman push --tls-verify=false --authfile $PULL_SECRET_FILE $OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE $OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE
    fi
}

export REPO_OVERRIDES=$(env | grep '_LOCAL_REPO=' | grep -o '^[^=]*')

# Skip the step in case of no overrides
if [[ ! -z "${REPO_OVERRIDES}" ]] ; then 
    build_local_release
fi
