#!/usr/bin/env bash
set -euo pipefail

# OVE (OpenShift Virtualization Edition) ISO building utilities
# Functions for creating agent ISOs without embedded registry

# Check if using a custom registry (not upstream quay.io or CI registry)
function is_custom_registry() {
  [[ ! "${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}" =~ quay\.io ]] && \
  [[ ! "${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}" =~ registry\.ci\.openshift\.org ]]
}

# Determine release image URL based on mirror configuration
function get_release_image_url() {
  if [[ "${MIRROR_IMAGES}" == "true" ]] && [[ -n "$(get_repo_overrides)" ]]; then
    echo "${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}"
  else
    echo "${OPENSHIFT_RELEASE_IMAGE}"
  fi
}

# Build OVE ISO using script method
function build_ove_iso_script() {
  local asset_dir=$1
  local release_image_url=$2
  local mirror_path_arg=$3
  local registry_cert_arg=$4

  ./hack/build-ove-image.sh \
    --pull-secret-file "${PULL_SECRET_FILE}" \
    --release-image-url "${release_image_url}" \
    --ssh-key-file "${SSH_KEY_FILE}" \
    --dir "${asset_dir}" \
    ${mirror_path_arg} \
    ${registry_cert_arg}
}

# Build OVE ISO using container method
function build_ove_iso_container() {
  local asset_dir=$1
  local release_image_url=$2

  # Build ISO in container
  make build-ove-iso-container \
    PULL_SECRET_FILE="${PULL_SECRET_FILE}" \
    RELEASE_IMAGE_URL="${release_image_url}" \
    ARCH=${ARCH}

  # Extract ISO from container
  ./hack/iso-from-container.sh

  # Move to asset directory
  local iso_name="agent-ove.${ARCH}.iso"
  echo "Moving ${iso_name} to ${asset_dir}"
  mv ./output-iso/${iso_name} "${asset_dir}"
}

# Create agent ISO without registry (OVE ISO)
function create_agent_iso_no_registry() {
  local asset_dir=${1}

  # Update release_info.json as its needed by CI tests
  save_release_info ${OPENSHIFT_RELEASE_IMAGE} ${OCP_DIR}

  AGENT_ISO_BUILDER_IMAGE=$(getAgentISOBuilderImage)

  # Extract agent-iso-builder source from container
  id=$(podman create --pull always --authfile "${PULL_SECRET_FILE}" "${AGENT_ISO_BUILDER_IMAGE}") && \
    podman cp "${id}":/src "${asset_dir}" && \
    podman rm "${id}"

  pushd .
  cd "${asset_dir}"/src

  # Determine release image URL
  local release_image_url=$(get_release_image_url)
  echo "build_ove_iso will use release image ${release_image_url}"

  # Prepare mirror and certificate arguments for script build method
  local mirror_path_arg=""
  local registry_cert_arg=""

  if [[ "${MIRROR_IMAGES}" == "true" ]]; then
    echo "Using pre-mirrored images from ${REGISTRY_DIR}"
    mirror_path_arg="--mirror-path ${REGISTRY_DIR}"

    # Add registry certificate if using custom registry
    if is_custom_registry && [[ -f "${REGISTRY_DIR}/certs/${REGISTRY_CRT}" ]]; then
      registry_cert_arg="--registry-cert ${REGISTRY_DIR}/certs/${REGISTRY_CRT}"
    fi
  fi

  # Build OVE ISO using selected method
  if [[ "${AGENT_ISO_NO_REGISTRY_BUILD_METHOD}" == "script" ]]; then
    build_ove_iso_script "${asset_dir}" "${release_image_url}" "${mirror_path_arg}" "${registry_cert_arg}"
  else
    build_ove_iso_container "${asset_dir}" "${release_image_url}"
  fi

  rm -rf "${asset_dir}"/src
  popd
}
