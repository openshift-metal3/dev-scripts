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

# Use the oc-mirror command to generate a tar file of the release image
function mirror_to_file() {

   config=${1}

   pushd ${WORKING_DIR}
   oc-mirror --v2 --config ${config} file://${WORKING_DIR} --ignore-release-signature
   popd
}

function publish_image() {

   config=${1}

   # Workaround: oc-mirror v2 doesn't respect registries.conf insecure setting
   # Temporarily add cert to system trust store for oc-mirror, then remove it
   cert_temporarily_added=false
   if [[ ! -z "${REGISTRY_INSECURE}" && "${REGISTRY_INSECURE,,}" == "true" ]]; then
      echo "WORKAROUND: Temporarily adding certificate to system trust for oc-mirror v2"

      if [[ "${REGISTRY_BACKEND}" = "podman" ]]; then
         if [[ -f "${REGISTRY_DIR}/certs/${REGISTRY_CRT}" ]]; then
            sudo cp ${REGISTRY_DIR}/certs/${REGISTRY_CRT} /etc/pki/ca-trust/source/anchors/
            sudo update-ca-trust
            cert_temporarily_added=true
         fi
      else
         # quay backend
         if [[ -f "${WORKING_DIR}/quay-install/quay-rootCA/rootCA.pem" ]]; then
            sudo cp ${WORKING_DIR}/quay-install/quay-rootCA/rootCA.pem /etc/pki/ca-trust/source/anchors/
            sudo update-ca-trust
            cert_temporarily_added=true
         fi
      fi
   fi

   pushd ${WORKING_DIR}
   oc-mirror --v2 --config ${config} --from file://${WORKING_DIR} docker://${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT} --ignore-release-signature
   popd

   # Remove the temporarily added certificate
   if [[ "${cert_temporarily_added}" == "true" ]]; then
      echo "WORKAROUND: Removing temporarily added certificate from system trust"
      if [[ "${REGISTRY_BACKEND}" = "podman" ]]; then
         sudo rm -f /etc/pki/ca-trust/source/anchors/${REGISTRY_CRT}
      else
         sudo rm -f /etc/pki/ca-trust/source/anchors/rootCA.pem
      fi
      sudo update-ca-trust
   fi

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
