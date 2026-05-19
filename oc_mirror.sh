#!/usr/bin/env bash
set -euxo pipefail

# Utility functions to create a local mirror registry using 'mirror-registry' and mirror
# a release using 'oc mirror'

function add_auth_to_pull_secret() {

   quay_auths=$1

   tmpauthfile=$(mktemp --tmpdir "quayauth--XXXXXXXXXX")
   _tmpfiles="$_tmpfiles $tmpauthfile"

   cat > "${tmpauthfile}" << EOF
{
  "auths": {
    "${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}": {
      "auth": "$quay_auths"
    }
  }
}
EOF

   cp ${tmpauthfile} ${REGISTRY_CREDS}
}

function update_docker_config() {

   if [[ -f ${DOCKER_CONFIG_FILE} ]]; then
      cp ${DOCKER_CONFIG_FILE} ${DOCKER_CONFIG_FILE}.old
   fi
   cp ${PULL_SECRET_FILE} ${DOCKER_CONFIG_FILE}

   # oc-mirror --v2 uses the podman auth store as its primary credential source,
   # ignoring --authfile for source registry auth. Explicitly refresh the CI registry
   # login so the podman auth store has fresh credentials.
   local ci_token=$(jq -r '.auths["registry.ci.openshift.org"].auth' ${PULL_SECRET_FILE} | base64 -d)
   local ci_user=$(echo "$ci_token" | cut -d: -f1)
   local ci_password=$(echo "$ci_token" | cut -d: -f2-)
   podman login registry.ci.openshift.org --username "$ci_user" --password "$ci_password" 2>/dev/null || true
}

function setup_quay_mirror_registry() {

   if sudo podman container exists registry; then
     echo "The podman registry is currently running and will cause a conflict with quay registry. Run \"registry_cleanup.sh\" to remove podman registry."
     exit 1
   fi

   mkdir -p ${WORKING_DIR}/quay-install
   pushd ${WORKING_DIR}/mirror-registry
   sudo ./mirror-registry install --quayHostname ${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT} --quayRoot ${WORKING_DIR}/quay-install/ --initUser ${REGISTRY_USER} --initPassword ${REGISTRY_PASS} --sslCheckSkip -v

   quay_auths=`echo -n "${REGISTRY_USER}:${REGISTRY_PASS}" | base64 -w0`

   add_auth_to_pull_secret ${quay_auths}
   popd
}

function create_file_imageset() {

   imageset=$1

   cat > "${imageset}" << EOF
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1
mirror:
  platform:
    # graph: true is intentionally omitted. When enabled, oc-mirror generates
    # an updateService.yaml manifest referencing the UpdateService CRD, which
    # does not exist during cluster bootstrap. This causes bootkube to loop
    # indefinitely trying to apply it, eventually timing out and failing the
    # rendezvous node installation. This is particularly an issue when
    # --mirror-path is used with the appliance build, since the updateService.yaml
    # generated here gets picked up via mirrorPath and embedded in the appliance ISO.
    release: $OPENSHIFT_RELEASE_IMAGE
  additionalImages:
  - name: registry.redhat.io/ubi8/ubi:latest
  # Required by the OVE ISO appliance config (additionalImages) so it is available
  # in the local mirror when building the appliance ISO with --mirror-path.
  - name: registry.redhat.io/rhel9/support-tools:latest
EOF

   if [[ "${AGENT_E2E_TEST_BOOT_MODE}" == "ISO_NO_REGISTRY" ]]; then
      append_ove_operators "${imageset}"
   fi

}

# Appends the operators section from the agent-iso-builder appliance-config.yaml
# to the imageset so operator images are included in the mirror and available
# to the appliance builder via --mirror-path.
function append_ove_operators() {

   local imageset=$1
   local full_version
   full_version=$(skopeo inspect --authfile "${PULL_SECRET_FILE}" docker://${OPENSHIFT_RELEASE_IMAGE} \
       | jq -r '.Labels["io.openshift.release"]')
   local major_minor
   major_minor=$(echo "${full_version}" | cut -d'.' -f1,2)
   local iso_builder_image="registry.ci.openshift.org/ocp/${major_minor}:agent-iso-builder"

   echo "Appending OVE operators from ${iso_builder_image} config/${major_minor}/appliance-config.yaml"

   # The agent-iso-builder image is a minimal image with no shell or python3,
   # so use podman cp to extract the file and parse it on the host.
   local tmpdir
   tmpdir=$(mktemp -d)
   _tmpfiles="$_tmpfiles $tmpdir"

   local cid
   cid=$(podman create --authfile "${PULL_SECRET_FILE}" "${iso_builder_image}")
   if ! podman cp "${cid}:/src/config/${major_minor}/appliance-config.yaml" "${tmpdir}/"; then
      podman rm "${cid}" > /dev/null
      return 1
   fi
   podman rm "${cid}" > /dev/null

   local operators_yaml
   operators_yaml=$(python3 -c "
import yaml
with open('${tmpdir}/appliance-config.yaml') as f:
    config = yaml.safe_load(f)
operators = config.get('operators')
if operators:
    print(yaml.dump(operators, default_flow_style=False))
")

   if [[ -n "${operators_yaml}" ]]; then
      echo "  operators:" >> "${imageset}"
      echo "${operators_yaml}" | sed 's/^/  /' >> "${imageset}"
   else
      echo "No operators found in appliance-config.yaml for version ${major_minor}"
   fi

}

# Use the oc-mirror command to generate a tar file of the release image
function mirror_to_file() {

   config=${1}

   pushd ${WORKING_DIR}
   oc-mirror --v2 -c ${config} --authfile ${PULL_SECRET_FILE} file://${WORKING_DIR} --ignore-release-signature --remove-signatures
   popd
}

function publish_image() {

   config=${1}

   pushd ${WORKING_DIR}
   oc-mirror --v2 --config ${config} --authfile ${PULL_SECRET_FILE} --from file://${WORKING_DIR} docker://${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT} --ignore-release-signature --remove-signatures
   popd

}

# Set up a mirror using the 'oc mirror' command
# The backend registry can be either 'podman' or 'quay'
function setup_oc_mirror() {

   update_docker_config

   tmpimageset=$(mktemp --tmpdir "imageset--XXXXXXXXXX")
   _tmpfiles="$_tmpfiles $tmpimageset"

   create_file_imageset $tmpimageset

   mirror_to_file $tmpimageset

   publish_image $tmpimageset

   # remove interim file
   rm ${WORKING_DIR}/mirror_*.tar
}
