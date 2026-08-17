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

  # shellcheck disable=SC2086 # mirror_path_arg and registry_cert_arg intentionally unquoted for word splitting
  ./hack/build-ove-image.sh \
    --pull-secret-file "${PULL_SECRET_FILE}" \
    --release-image-url "${release_image_url}" \
    --ssh-key-file "${SSH_KEY_FILE}" \
    ${APPLIANCE_IMAGE:+--appliance-image "${APPLIANCE_IMAGE}"} \
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
    ARCH="${ARCH}"

  # Extract ISO from container
  ./hack/iso-from-container.sh

  # Move to asset directory
  local iso_name="agent-ove.${ARCH}.iso"
  echo "Moving ${iso_name} to ${asset_dir}"
  mv "./output-iso/${iso_name}" "${asset_dir}"
}

# Inject the local SSH public key into a pre-built OVE ISO's embedded live ignition.
#
# Locally-built ISOs (build-ove-image.sh --ssh-key-file) but a pre-built ISO
# fetched via AGENT_OVE_ISO_SOURCE may not. This adds the key to the 'core' user.
# Note that if the pre-built ISO already has the ssh key this will not create
# a duplicate but it will overwrite the current key.
function inject_ssh_key_into_ove_iso() {
  local iso="${1}"
  local dir base tmp ssh_pub coreos_installer

  if [[ ! -f "${SSH_KEY_FILE}" ]]; then
    echo "Warning: SSH_KEY_FILE (${SSH_KEY_FILE}) not found; skipping SSH key injection." >&2
    return 0
  fi

  dir=$(dirname "${iso}")
  base=$(basename "${iso}")
  ssh_pub=$(cat "${SSH_KEY_FILE}")
  tmp=$(mktemp -d)

  echo "Injecting SSH key from ${SSH_KEY_FILE} into ${iso}"

  coreos_installer=(sudo podman run --privileged --rm -v /run/udev:/run/udev
    -v "${dir}:/data" -v "${tmp}:/cfg" -w /data quay.io/coreos/coreos-installer:release)

  # Extract the ISO's existing embedded live ignition so we can preserve it.
  if ! "${coreos_installer[@]}" iso ignition show "/data/${base}" > "${tmp}/iso.ign" 2>/dev/null \
      || ! jq -e . "${tmp}/iso.ign" >/dev/null 2>&1; then
    # No embedded ignition (or unreadable) - start from a minimal 3.2.0 config.
    echo '{"ignition":{"version":"3.2.0"}}' > "${tmp}/iso.ign"
  fi

  # Append our key to the 'core' user (create it if absent), keeping any existing keys.
  jq --arg key "${ssh_pub}" '
    .passwd = (.passwd // {}) |
    .passwd.users = (.passwd.users // []) |
    if any(.passwd.users[]; .name == "core")
    then .passwd.users |= map(
           if .name == "core"
           then .sshAuthorizedKeys = ((.sshAuthorizedKeys // []) + [$key] | unique)
           else . end)
    else .passwd.users += [{"name": "core", "sshAuthorizedKeys": [$key]}]
    end
  ' "${tmp}/iso.ign" > "${tmp}/iso-ssh.ign"

  # Re-embed the augmented ignition in place (-f overwrites the existing one).
  "${coreos_installer[@]}" iso ignition embed -f -i "/cfg/iso-ssh.ign" "/data/${base}"

  rm -rf "${tmp}"
  echo "SSH key injected into ${iso}"
}

# Obtain a pre-built OVE ISO from AGENT_OVE_ISO_SOURCE instead of building it locally.
# The resulting ISO is placed at "${asset_dir}/agent-ove.${ARCH}.iso", where
# get_agent_iso_no_registry looks for it. The source may be:
#   - a quay.io/redhat-user-workloads/... container image (ISO extracted from the image)
#   - a local path/filename to an already-downloaded ISO
#
# Direct https downloads (e.g. mirror.openshift.com / the Red Hat content-gateway) are
# not supported here because they require Red Hat SSO authentication. Download such ISOs
# separately and pass the resulting local file path as AGENT_OVE_ISO_SOURCE.
function fetch_agent_iso_no_registry() {
  local asset_dir=${1}
  local dest="${asset_dir}/agent-ove.${ARCH}.iso"

  mkdir -p "${asset_dir}"

  if [[ "${AGENT_OVE_ISO_SOURCE}" == *"redhat-user-workloads"* ]]; then
    # Intermediate build published as a container image - extract the ISO from it.
    echo "Extracting OVE ISO from container image ${AGENT_OVE_ISO_SOURCE}"
    local id
    id=$(sudo podman create --arch amd64 "${AGENT_OVE_ISO_SOURCE}")
    sudo podman cp "${id}:/agent-ove.x86_64.iso" "${dest}"
    sudo podman rm "${id}"
  elif [[ "${AGENT_OVE_ISO_SOURCE}" =~ ^https?:// ]]; then
    # Direct URLs are not supported - they require Red Hat SSO authentication.
    echo "Error: direct URL downloads are not supported for AGENT_OVE_ISO_SOURCE." >&2
    echo "       The content-gateway/mirror URLs require Red Hat SSO authentication." >&2
    echo "       Download the ISO separately and set AGENT_OVE_ISO_SOURCE to the local file path," >&2
    echo "       or use a quay.io/redhat-user-workloads/... container image reference." >&2
    exit 1
  else
    # Treat as a local path/filename to an already-downloaded ISO.
    echo "Using local OVE ISO ${AGENT_OVE_ISO_SOURCE}"
    if [[ ! -f "${AGENT_OVE_ISO_SOURCE}" ]]; then
      echo "Error: OVE ISO file not found: ${AGENT_OVE_ISO_SOURCE}" >&2
      exit 1
    fi
    cp "${AGENT_OVE_ISO_SOURCE}" "${dest}"
  fi

  # A pre-built ISO has no SSH key baked in - add ours so we can ssh into the
  # live/bootstrap OVE environment (and the installed nodes once it propagates).
  inject_ssh_key_into_ove_iso "${dest}"

  echo "OVE ISO available at ${dest}"
}

# Create agent ISO without registry (OVE ISO)
function create_agent_iso_no_registry() {
  local asset_dir=${1}

  # Update release_info.json as its needed by CI tests
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

  # Determine release image URL
  local release_image_url
  release_image_url=$(get_release_image_url)
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

# Deletes all files and directories under asset_dir
# example, ocp/ostest/iso_builder/4.19.* 
# except the final generated ISO file (agent-ove.${ARCH}.iso),
# to free up disk space while preserving the built artifact.
# Note: This optional cleanup is relevant only when the
# AGENT_CLEANUP_ISO_BUILDER_CACHE_LOCAL_DEV is set as as true, 
function cleanup_diskspace_agent_iso_noregistry() {
 local asset_dir=${1%/}  # Remove trailing slash if present

  # Iterate over all versioned directories
  for dir in "$asset_dir"/[0-9]*.[0-9]*.*; do
    [ -d "$dir" ] || continue

    # Delete all files and symlinks except the agent-ove ISO
    sudo find "$dir" \( -type f -o -type l \) ! -name "agent-ove.${ARCH}.iso" -delete

    # Remove any empty directories left behind
    sudo find "$dir" -type d -empty -delete
  done
}
