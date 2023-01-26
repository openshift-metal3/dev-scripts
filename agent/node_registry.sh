#!/usr/bin/env bash
# shellcheck source=/dev/null
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

source "$SCRIPTDIR"/common.sh
source "$SCRIPTDIR"/oc_mirror.sh
source "$SCRIPTDIR"/utils.sh

function put_file_to_host() {

  local_file=$1

  node0_ip=$(get_node0_ip)

  ssh_opts=(-o 'StrictHostKeyChecking=no' -q core@${node0_ip})

  until ssh "${ssh_opts[@]}" "[[ -f /etc/hosts ]]"
  do
     echo "Waiting to scp $local_file"
     sleep 30s;
  done

  scp $local_file core@${node0_ip}:/home/core

}

function set_bootstrap_imageset() {

   # Create imageset only with images needed for bootstrap
   imageset=$1

   latest_release=$(oc-mirror list releases --channel candidate-${OPENSHIFT_RELEASE_STREAM}| tail -n1)

   if [[ ${#OPENSHIFT_RELEASE_TAG} = 64 ]] && [[ ${OPENSHIFT_RELEASE_TAG} =~ [:alnum:] ]]; then
      mapfile -t release_images < <( oc adm release info quay.io/openshift-release-dev/ocp-release@sha256:${OPENSHIFT_RELEASE_TAG} -o json | jq -r '.references.spec.tags[] | .name + " " + .from.name' )
      echo "Getting release_images for digest"
   else
      mapfile -t release_images < <( oc adm release info quay.io/openshift-release-dev/ocp-release:${OPENSHIFT_RELEASE_TAG} -o json | jq -r '.references.spec.tags[] | .name + " " + .from.name' )
      echo "NOT Getting release_images for digest"
   fi

   cat > "${imageset}" << EOF
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v1alpha2
archiveSize: 8
storageConfig:
  local:
    path: metadata
mirror:
  platform:
    architectures:
      - "amd64"
    channels:
      - name: candidate-${OPENSHIFT_RELEASE_STREAM}
        minVersion: $latest_release
        maxVersion: $latest_release
        type: ocp
  additionalImages:
    - name: registry.redhat.io/ubi8/ubi:latest
  blockedImages:
EOF

   for image_info in "${release_images[@]}"; do
        read -r image_name image_ref <<< $image_info
        case "$image_name" in agent-installer-api-server | must-gather | hyperkube | cloud-credential-operator | cluster-policy-controller | agent-installer-orchestrator | pod | cluster-config-operator | cluster-etcd-operator | cluster-kube-controller-manager-operator | cluster-kube-scheduler-operator | agent-installer-node-agent | machine-config-operator | etcd | cluster-bootstrap | cluster-ingress-operator | cluster-kube-apiserver-operator | baremetal-installer | keepalived-ipfailover | baremetal-runtimecfg | coredns | installer)
                        >&2 echo "Not blocking $image_name";;
                *)
                        >&2 echo "Blocking $image_name"
                        cat >> "${imageset}" <<EOF
    - name: "$image_ref"
EOF
                        ;;
        esac
   done

}


function create_container_image_file() {

   tmpimageset=$(mktemp --tmpdir "imageset--XXXXXXXXXX")
   _tmpfiles="$_tmpfiles $tmpimageset"

   set_bootstrap_imageset $tmpimageset

   mirror_to_file $tmpimageset
}

function put_tools_to_host() {

   # Get libpod registry container image
   libpod_image=./registry_image.tar
   if [[ -f ${libpod_image} ]]; then
      sudo rm ${libpod_image}
   fi
   sudo podman save ${DOCKER_REGISTRY_IMAGE} -o ${libpod_image}
   put_file_to_host ${libpod_image}
   sudo rm ${libpod_image}

   # Run htpasswd locally and scp the htpasswd file
   # The registry requires a bcrypt encrypted password and htpasswd is not in CoreOS
   htpasswd -bBc ./htpasswd ${REGISTRY_USER} ${REGISTRY_PASS}
   put_file_to_host ./htpasswd

   # Get oc-mirror binary from the release image
   oc_mirror_image=$(oc adm release info quay.io/openshift-release-dev/ocp-release:4.12.0-x86_64 --image-for oc-mirror)

   tmp_oc_mirror_dir="$(mktemp --directory)"
   oc image extract --path /usr/bin/oc-mirror:$tmp_oc_mirror_dir ${oc_mirror_image} --confirm
   put_file_to_host $tmp_oc_mirror_dir/oc-mirror

   # scp tarfile with container images
   archive_file="$(ls ${oc_mirror_dir}/mirror_seq*)"
   put_file_to_host ${archive_file}

}
