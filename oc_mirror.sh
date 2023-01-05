#!/usr/bin/env bash
set -euxo pipefail

# Utility functions to create a local mirror registry using 'mirror-registry' and mirror
# a release using 'oc mirror'

function add_auth_to_pull_secret() {

   quay_auths=$1

   tmpauthfile=$(mktemp --tmpdir "quayauth--XXXXXXXXXX")
   _tmpfiles="$_tmpfiles $tmpauthfile"
   tmppullsecret=$(mktemp --tmpdir "pullsecret--XXXXXXXXXX")
   _tmpfiles="$_tmpfiles $tmppullsecret"


   cat > "${tmpauthfile}" << EOF
{
  "auths": {
    "${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}": {
      "auth": "$quay_auths"
    }
  }
}
EOF

   jq -s '.[0] * .[1]' ${tmpauthfile} ${PULL_SECRET_FILE} > ${tmppullsecret}
   cp ${tmppullsecret} ${PULL_SECRET_FILE}

}

function update_docker_config() {

   if [[ -f ${DOCKER_CONFIG_FILE} ]]; then
      cp ${DOCKER_CONFIG_FILE} ${DOCKER_CONFIG_FILE}.old
   fi
   cp ${PULL_SECRET_FILE} ${DOCKER_CONFIG_FILE}
}

function setup_quay_mirror_registry() {

   mkdir -p ${WORKING_DIR}/quay-install
   pushd ${WORKING_DIR}/mirror-registry
   sudo ./mirror-registry install --quayHostname ${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT} --quayRoot ${WORKING_DIR}/quay-install/ --initUser ${REGISTRY_USER} --initPassword ${REGISTRY_PASS} --sslCheckSkip -v

   quay_auths=`echo -n "${REGISTRY_USER}:${REGISTRY_PASS}" | base64 -w0`

   add_auth_to_pull_secret ${quay_auths}
   popd
}

# Mirror the upstream channel directly to the local registry
function mirror_to_mirror_publish() {

   # Create imageset containing the local URL and the OCP release to mirror
   tmpimageset=$(mktemp --tmpdir "imageset--XXXXXXXXXX")
   _tmpfiles="$_tmpfiles $tmpimageset"

   cat > "${tmpimageset}" << EOF
apiVersion: mirror.openshift.io/v1alpha2
kind: ImageSetConfiguration
archiveSize: 4
storageConfig:
  registry:
    imageURL: ${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/origin:latest
    skipTLS: true
mirror:
  platform:
    channels:
    - name: candidate-${OPENSHIFT_RELEASE_STREAM}
      type: ocp
  additionalImages:
  - name: registry.redhat.io/ubi8/ubi:latest
EOF

   pushd ${WORKING_DIR}
   oc mirror --dest-skip-tls --config ${tmpimageset} docker://${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}
   popd

}

function set_full_imageset() {

   # Create imageset with all images from releaseImage
   imageset=$1

   cat > "${imageset}" << EOF
apiVersion: mirror.openshift.io/v1alpha2
kind: ImageSetConfiguration
archiveSize: 24
storageConfig:
  local:
    path: metadata
mirror:
  platform:
    architectures:
      - "amd64"
    channels:
      - name: candidate-${OPENSHIFT_RELEASE_STREAM}
        type: ocp
  additionalImages:
  - name: registry.redhat.io/ubi8/ubi:latest
EOF

}

# Use the oc-mirror command to generate a tar file of the release image
function mirror_to_file() {

   config=${1}

   pushd ${WORKING_DIR}
   oc_mirror_dir=$(mktemp --tmpdir -d "oc-mirror-files--XXXXXXXXXX")
   _tmpfiles="$_tmpfiles $oc_mirror_dir"
   oc-mirror --config ${config} file://${oc_mirror_dir} --ignore-history
   archive_file="$(ls ${oc_mirror_dir}/mirror_seq*)"
   popd

}

function publish_image() {

   pushd ${WORKING_DIR}
   oc-mirror --from $archive_file docker://${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT} --skip-metadata-check
   popd

}

# function publish_bootstrap_image() {
#
# }

# Set up a mirror using the 'oc mirror' command
# The backend registry can be either 'podman' or 'quay'
function setup_oc_mirror() {

   update_docker_config

   if [ -z "${OC_MIRROR_TO_FILE}" ]; then
       mirror_to_mirror_publish
   else
       tmpimageset=$(mktemp --tmpdir "imageset--XXXXXXXXXX")
       _tmpfiles="$_tmpfiles $tmpimageset"

       set_full_imageset $tmpimageset

       mirror_to_file $tmpimageset

       publish_image
   fi
}
