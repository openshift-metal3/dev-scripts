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

# Function definitions

# Prepares the registry directory structure for the OpenShift appliance builder.
#
# When building OVE ISOs with mirror-path support, the appliance expects a specific
# directory layout with pre-mirrored registry data and oc-mirror output files. This
# function organizes the registry directory created by setup_release_mirror() into
# the format expected by the appliance builder.
#
# Directory structure created:
#   REGISTRY_DIR/
#     ├── cache/<version>-<arch>/     # Where appliance will write the ISO
#     ├── data/                        # Pre-mirrored registry data (from oc-mirror)
#     ├── working-dir/                 # oc-mirror YAML files (IDMS, CatalogSources)
#     └── results-*/                   # oc-mirror mapping.txt
#
# The appliance uses this directory via the --mirror-path flag to skip running
# oc-mirror during the build and instead use the pre-mirrored images directly.
function prepare_registry_dir_for_appliance() {
    echo "Preparing registry directory structure for appliance..."

    # Create the cache directory structure expected by appliance
    # Appliance expects: mirror-path/cache/<version-arch> (ISO output)
    # Appliance will read registry data directly from mirror-path/data

    # Extract version from release image to create cache subdirectory
    # Appliance creates cache dir in format: cache/<version>-<arch>
    VERSION=$(skopeo inspect --authfile ${PULL_SECRET_FILE} docker://${OPENSHIFT_RELEASE_IMAGE} | jq -r '.Labels["io.openshift.release"]')
    ARCH=$(uname -m)
    CACHE_SUBDIR="${VERSION}-${ARCH}"
    mkdir -p ${REGISTRY_DIR}/cache/${CACHE_SUBDIR}

    # Copy YAML files and mapping.txt to registry directory so appliance can find them
    if [[ -d ${WORKING_DIR}/working-dir ]]; then
        cp -r ${WORKING_DIR}/working-dir ${REGISTRY_DIR}/
    fi

    # Copy results directory containing mapping.txt
    for results_dir in ${WORKING_DIR}/results-*; do
        if [[ -d "$results_dir" ]]; then
            cp -r "$results_dir" ${REGISTRY_DIR}/
        fi
    done

    # Append IDMS entry for local dev-scripts registry to existing idms-oc-mirror.yaml
    # This ensures the local registry can be accessed from the installed cluster
    echo "Appending IDMS entry for local registry"

    # Local dev-scripts registry
    local local_registry="${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}"

    echo "Creating IDMS mapping: ${local_registry} -> ${local_registry}"

    # Append mirror entry to existing IDMS file
    cat >> ${REGISTRY_DIR}/working-dir/cluster-resources/idms-oc-mirror.yaml << EOF
  - mirrors:
    - ${local_registry}
    source: ${local_registry}
EOF

    echo "Custom registry IDMS entry appended to ${REGISTRY_DIR}/working-dir/cluster-resources/idms-oc-mirror.yaml"

    echo "Registry directory prepared for appliance"
}

# To replace an image entry in the openshift release image, set <ENTRYNAME>_LOCAL_REPO so that:
# - ENTRYNAME matches an uppercase version of the name in the release image with "-" converted to "_"
# - The var value must point to an already locally cloned repo
#
# To specify a custom Dockerfile set <ENTRYNAME>_DOCKERFILE, as a relative path of the Dockerfile
# within the configured repo
#
# To specify a custom image name, set <ENTRYNAME>_IMAGE with the required image name
#
# For example, to use a custom installer and assisted-service image:
# export INSTALLER_LOCAL_REPO=~/go/src/github.com/openshift/installer
# export INSTALLER_DOCKERFILE=images/installer/Dockerfile.ci
# export ASSISTED_SERVICE_LOCAL_REPO=~/git/assisted-service
# export ASSISTED_SERVICE_DOCKERFILE=Dockerfile.assisted-service.ocp
# export ASSISTED_SERVICE_IMAGE=agent-installer-api-server

function build_local_release() {
    # Sanity checks
    if [[ -z "${MIRROR_IMAGES}" || "${MIRROR_IMAGES,,}" == "false" ]]; then
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

        # Manage an additional build arg
        IMAGE_BUILD_ARG_VALUE=${IMAGE_VAR/_LOCAL_REPO}_BUILD_ARG
        IMAGE_BUILD_ARG=${!IMAGE_BUILD_ARG_VALUE:-}

        sudo podman build --network host --authfile $PULL_SECRET_FILE -t ${!IMAGE_VAR} -f $IMAGE_DOCKERFILE --build-arg "${IMAGE_BUILD_ARG}" .
        cd -
        sudo podman push --tls-verify=false --authfile $PULL_SECRET_FILE ${!IMAGE_VAR} ${!IMAGE_VAR}

        FINAL_IMAGE_NAME=${IMAGE_VAR/_LOCAL_REPO}_IMAGE
        FINAL_IMAGE=${!FINAL_IMAGE_NAME:-}
        if [[ -z "$FINAL_IMAGE" ]]; then
            FINAL_IMAGE=$(echo ${IMAGE_VAR/_LOCAL_REPO} | tr '[:upper:]_' '[:lower:]-')
        fi

        OLDIMAGE=$(sudo podman run --rm --authfile $PULL_SECRET_FILE $OPENSHIFT_RELEASE_IMAGE image $FINAL_IMAGE)
        echo "RUN sed -i 's%$OLDIMAGE%${!IMAGE_VAR}%g' /release-manifests/*" >> $DOCKERFILE
    done

    # Publish the new release in the local registry
    if [[ ! -z "${MIRROR_IMAGES}" && "${MIRROR_IMAGES,,}" != "false" ]]; then
        sudo podman image build --authfile $PULL_SECRET_FILE -t $OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE -f $DOCKERFILE
        sudo podman push --tls-verify=false --authfile $PULL_SECRET_FILE $OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE $OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE
    fi
}

# Main execution

early_deploy_validation
write_pull_secret

# Release mirroring could be required by the subsequent steps
# even if the current one will be skipped
if [[ "${MIRROR_IMAGES}" == "true" ]]; then
   setup_release_mirror
fi

export REPO_OVERRIDES=$(get_repo_overrides)

# Skip the step in case of no overrides
if [[ ! -z "${REPO_OVERRIDES}" ]] ; then
    build_local_release

    # Extract openshift-install from the newly built release image, in case it was updated
    extract_command "${OPENSHIFT_INSTALLER_CMD}" "${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}" "${OCP_DIR}"
fi

# Prepare registry directory for appliance if using ISO_NO_REGISTRY
if [[ "${MIRROR_IMAGES}" == "true" && "${AGENT_E2E_TEST_BOOT_MODE}" == "ISO_NO_REGISTRY" ]]; then
    prepare_registry_dir_for_appliance
fi