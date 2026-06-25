#!/usr/bin/env bash
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
ARCH=$(uname -m)

LOGDIR="${SCRIPTDIR}/logs"
source "$SCRIPTDIR/logging.sh"
source "$SCRIPTDIR/common.sh"
source "$SCRIPTDIR/network.sh"
source "$SCRIPTDIR/utils.sh"
source "$SCRIPTDIR/validation.sh"
source "$SCRIPTDIR/release_info.sh"
source "$SCRIPTDIR/agent/common.sh"

early_deploy_validation

function is_custom_registry() {
  [[ ! "${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}" =~ quay\.io ]] && \
  [[ ! "${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}" =~ registry\.ci\.openshift\.org ]]
}

function get_release_image_url() {
  if [[ "${MIRROR_IMAGES}" == "true" ]] && [[ -n "$(get_repo_overrides)" ]]; then
    echo "${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}"
  else
    echo "${OPENSHIFT_RELEASE_IMAGE}"
  fi
}

function build_ove_iso_script() {
  local asset_dir=$1
  local release_image_url=$2
  local mirror_path_arg=$3
  local registry_cert_arg=$4

  ./hack/build-ove-image.sh \
    --pull-secret-file "${PULL_SECRET_FILE}" \
    --release-image-url "${release_image_url}" \
    --ssh-key-file "${SSH_KEY_FILE}" \
    ${APPLIANCE_IMAGE:+--appliance-image "${APPLIANCE_IMAGE}"} \
    --dir "${asset_dir}" \
    # shellckeck disable=SC2086 # build-ove-image.sh doesn't handle empty args
    ${mirror_path_arg} \
    # shellckeck disable=SC2086 # build-ove-image.sh doesn't handle empty args
    ${registry_cert_arg}
}

function build_ove_iso_container() {
  local asset_dir=$1
  local release_image_url=$2

  make build-ove-iso-container \
    PULL_SECRET_FILE="${PULL_SECRET_FILE}" \
    RELEASE_IMAGE_URL="${release_image_url}" \
    ARCH="${ARCH}"

  ./hack/iso-from-container.sh

  local iso_name="agent-ove.${ARCH}.iso"
  echo "Moving ${iso_name} to ${asset_dir}"
  mv "./output-iso/${iso_name}" "${asset_dir}"
}

function create_agent_iso_no_registry() {
  local asset_dir=${1}

  save_release_info "${OPENSHIFT_RELEASE_IMAGE}" "${OCP_DIR}"

  local src_dir
  if [[ -n "${OPENSHIFT_AGENT_INSTALLER_UTILS_PATH:-}" ]]; then
    src_dir="${OPENSHIFT_AGENT_INSTALLER_UTILS_PATH}/tools/iso_builder"
  else
    AGENT_ISO_BUILDER_IMAGE=$(getAgentISOBuilderImage)
    id=$(podman create --pull always --authfile "${PULL_SECRET_FILE}" "${AGENT_ISO_BUILDER_IMAGE}") && \
      podman cp "${id}":/src "${asset_dir}" && \
      podman rm "${id}"
    src_dir="${asset_dir}/src"
  fi

  pushd .
  cd "${src_dir}"

  local release_image_url
  release_image_url=$(get_release_image_url)
  echo "build_ove_iso will use release image ${release_image_url}"

  local mirror_path_arg=""
  local registry_cert_arg=""

  if [[ "${MIRROR_IMAGES}" == "true" ]]; then
    echo "Using pre-mirrored images from ${REGISTRY_DIR}"
    mirror_path_arg="--mirror-path ${REGISTRY_DIR}"

    if is_custom_registry && [[ -f "${REGISTRY_DIR}/certs/${REGISTRY_CRT}" ]]; then
      registry_cert_arg="--registry-cert ${REGISTRY_DIR}/certs/${REGISTRY_CRT}"
    fi
  fi

  if [[ "${AGENT_ISO_NO_REGISTRY_BUILD_METHOD}" == "script" ]]; then
    build_ove_iso_script "${asset_dir}" "${release_image_url}" "${mirror_path_arg}" "${registry_cert_arg}"
  else
    build_ove_iso_container "${asset_dir}" "${release_image_url}"
  fi

  rm -rf "${asset_dir}"/src
  popd
}

function assert_agent_no_registry_iso_size(){
  agent_iso_no_registry=$(get_agent_iso_no_registry)
  iso_size=$(stat -c%s "$agent_iso_no_registry")

  iso_size_limit=$((AGENT_OVE_ISO_SIZE * 1024 * 1024 * 1024))

  if (( iso_size > iso_size_limit )); then
    echo "Error: OVE ISO size of $agent_iso_no_registry is ${iso_size}, which exceeds the ${AGENT_OVE_ISO_SIZE}GB limit."
    exit 1
  fi
}

function cleanup_diskspace_agent_iso_noregistry() {
  local asset_dir=${1%/}

  for dir in "$asset_dir"/[0-9]*.[0-9]*.*; do
    [ -d "$dir" ] || continue

    echo "Cleaning up directory: $dir"

    sudo find "$dir" \( -type f -o -type l \) ! -name "agent-ove.${ARCH}.iso" -delete

    sudo find "$dir" -type d -empty -delete
  done
}

# Main
if [[ "${AGENT_E2E_TEST_BOOT_MODE}" != "ISO_NO_REGISTRY" ]]; then
    echo "Skipping OVE ISO build: AGENT_E2E_TEST_BOOT_MODE=${AGENT_E2E_TEST_BOOT_MODE}"
    exit 0
fi

if agent_iso=$(get_agent_iso_no_registry 2>/dev/null); then
    echo "OVE ISO already exists at ${agent_iso}, skipping build"
    exit 0
fi

asset_dir=${AGENT_OVE_ISO_PATH}/iso_builder
mkdir -p "${asset_dir}"

create_agent_iso_no_registry "${asset_dir}"

assert_agent_no_registry_iso_size

if [[ "$AGENT_CLEANUP_ISO_BUILDER_CACHE_LOCAL_DEV" == "true" ]]; then
    cleanup_diskspace_agent_iso_noregistry "${asset_dir}"
fi

if [[ "${MIRROR_IMAGES}" == "true" ]]; then
    echo "Cleaning up registry data at ${REGISTRY_DIR} to save disk space"
    sudo rm -rf "${REGISTRY_DIR}/data"
    echo "Registry data cleanup complete"
fi

echo "OVE ISO build complete"
