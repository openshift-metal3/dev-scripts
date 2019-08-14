eval "$(go env)"

export OPENSHIFT_INSTALL_PATH="$GOPATH/src/github.com/openshift/installer"
export OPENSHIFT_INSTALL_DATA="$OPENSHIFT_INSTALL_PATH/data/data"
export BASE_DOMAIN=${BASE_DOMAIN:-test.metalkube.org}
export CLUSTER_NAME=${CLUSTER_NAME:-ostest}
export CLUSTER_DOMAIN="${CLUSTER_NAME}.${BASE_DOMAIN}"
export SSH_PUB_KEY="${SSH_PUB_KEY:-$(cat $HOME/.ssh/id_rsa.pub)}"
export EXTERNAL_SUBNET=${EXTERNAL_SUBNET:-"192.168.111.0/24"}
export DNS_VIP=${DNS_VIP:-"192.168.111.2"}
export KNI_INSTALL_FROM_GIT=true

#
# See https://origin-release.svc.ci.openshift.org/ for release details
#
# The release we default to here is pinned and known to work with the
# baremetal platform in openshift-installer
#
export OPENSHIFT_RELEASE_IMAGE_OVERRIDE="${OPENSHIFT_RELEASE_IMAGE_OVERRIDE:-registry.svc.ci.openshift.org/ocp/release:4.2.0-0.ci-2019-08-14-165546}"
export KNI_INSTALL_FROM_GIT=true

function extract_installer() {
    local release_image
    local outdir

    release_image="$1"
    outdir="$2"

    extract_dir=$(mktemp -d "installer--XXXXXXXXXX")


    echo "${PULL_SECRET}" > "${extract_dir}/pullsecret"
    oc adm release extract --registry-config "${extract_dir}/pullsecret" --command=openshift-install --to "${extract_dir}" "${release_image}"
    mv "${extract_dir}/openshift-install" "${outdir}"
    export OPENSHIFT_INSTALLER="${outdir}/openshift-install"

    rm -rf "${extract_dir}"
}

function clone_installer() {
  # Clone repo, if not already present
  if [[ ! -d $OPENSHIFT_INSTALL_PATH ]]; then
    sync_repo_and_patch go/src/github.com/openshift/installer https://github.com/openshift/installer.git
  fi
}

function build_installer() {
  # Build installer
  pushd .
  cd $OPENSHIFT_INSTALL_PATH
  RELEASE_IMAGE="$OPENSHIFT_RELEASE_IMAGE_OVERRIDE" TAGS="libvirt baremetal" hack/build.sh
  popd

  export OPENSHIFT_INSTALLER="$OPENSHIFT_INSTALL_PATH/bin/openshift-install"
}

function generate_ocp_install_config() {
    local outdir

    outdir="$1"

    deploy_kernel=$(master_node_val 0 "driver_info.deploy_kernel")
    deploy_ramdisk=$(master_node_val 0 "driver_info.deploy_ramdisk")

    # Always deploy with 0 workers by default.  We do not yet support
    # automatically deploying workers at install time anyway.  We can scale up
    # the worker MachineSet after deploying the baremetal-operator
    #
    # TODO - Change worker replicas to ${NUM_WORKERS} once the machine-api-operator
    # deploys the baremetal-operator

    cat > "${outdir}/install-config.yaml" << EOF
apiVersion: v1beta4
baseDomain: ${BASE_DOMAIN}
networking:
  machineCIDR: ${EXTERNAL_SUBNET}
metadata:
  name: ${CLUSTER_NAME}
compute:
- name: worker
  replicas: 0
controlPlane:
  name: master
  replicas: ${NUM_MASTERS}
  platform:
    baremetal: {}
platform:
  baremetal:
    dnsVIP: ${DNS_VIP}
    hosts:
$(master_node_map_to_install_config $NUM_MASTERS)
pullSecret: |
  $(echo $PULL_SECRET | jq -c .)
sshKey: |
  ${SSH_PUB_KEY}
EOF
}
