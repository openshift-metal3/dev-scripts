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

function create_registry_imageset() {

   imageset=$1

   cat > "${imageset}" << EOF
apiVersion: mirror.openshift.io/v1alpha2
kind: ImageSetConfiguration
archiveSize: 4
storageConfig:
  registry:
    imageURL: ${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/origin:latest
    skipTLS: true
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

function create_file_imageset() {

   imageset=$1

   cat > "${imageset}" << EOF
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1
mirror:
  platform:
    graph: true
    release: $OPENSHIFT_RELEASE_IMAGE
  additionalImages:
  - name: registry.redhat.io/ubi8/ubi:latest
EOF

}

# Mirror the upstream channel directly to the local registry
# Note that this method is only valid with oc mirror v1
function mirror_to_mirror_publish() {

   # Create imageset containing the local URL and the OCP release to mirror
   tmpimageset=$(mktemp --tmpdir "imageset--XXXXXXXXXX")
   _tmpfiles="$_tmpfiles $tmpimageset"

   create_registry_imageset $tmpimageset

   pushd ${WORKING_DIR}
   oc mirror --dest-skip-tls --config ${tmpimageset} docker://${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}
   popd
}

# Use the oc-mirror command to generate a tar file of the release image
function mirror_to_file() {

   config=${1}

   pushd ${WORKING_DIR}
   oc-mirror --v2 --config ${config} file://${WORKING_DIR}
   popd
}

function publish_image() {

   config=${1}

   pushd ${WORKING_DIR}
   oc-mirror --v2 --config ${config} --from file://${WORKING_DIR} docker://${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}
   popd

}

# Set up a mirror using the 'oc mirror' command
# The backend registry can be either 'podman' or 'quay'
function setup_oc_mirror() {

   update_docker_config

   if [ -z "${OC_MIRROR_TO_FILE}" ]; then
       mirror_to_mirror_publish
   else
       tmpimageset=$(mktemp --tmpdir "imageset--XXXXXXXXXX")
       _tmpfiles="$_tmpfiles $tmpimageset"

       create_file_imageset $tmpimageset

       mirror_to_file $tmpimageset

       publish_image $tmpimageset

       # remove interim file
       rm ${WORKING_DIR}/mirror_*.tar
   fi
}
