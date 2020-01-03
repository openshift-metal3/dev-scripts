eval "$(go env)"

export BASE_DOMAIN=${BASE_DOMAIN:-test.metalkube.org}
export CLUSTER_NAME=${CLUSTER_NAME:-ostest}
export CLUSTER_DOMAIN="${CLUSTER_NAME}.${BASE_DOMAIN}"
export SSH_PUB_KEY="${SSH_PUB_KEY:-$(cat $HOME/.ssh/id_rsa.pub)}"
export NETWORK_TYPE=${NETWORK_TYPE:-"OpenShiftSDN"}
export EXTERNAL_SUBNET=${EXTERNAL_SUBNET:-"192.168.111.0/24"}
export MIRROR_IP=${MIRROR_IP:-"172.22.0.1"}
export DNS_VIP=${DNS_VIP:-"192.168.111.2"}
export LOCAL_REGISTRY_DNS_NAME=${LOCAL_REGISTRY_DNS_NAME:-"virthost.${CLUSTER_NAME}.${BASE_DOMAIN}"}

function extract_command() {
    local release_image
    local cmd
    local outdir
    local extract_dir

    cmd="$1"
    release_image="$2"
    outdir="$3"

    extract_dir=$(mktemp -d "installer--XXXXXXXXXX")
    pullsecret_file=$(mktemp "pullsecret--XXXXXXXXXX")

    echo "${PULL_SECRET}" > "${pullsecret_file}"
    oc adm release extract --registry-config "${pullsecret_file}" --command=$cmd --to "${extract_dir}" ${release_image}

    mv "${extract_dir}/${cmd}" "${outdir}"
    rm -rf "${extract_dir}"
    rm -rf "${pullsecret_file}"
}

# Let's always grab the `oc` from the release we're using.
function extract_oc() {
    extract_dir=$(mktemp -d "installer--XXXXXXXXXX")
    extract_command oc "$1" "${extract_dir}"
    sudo mv "${extract_dir}/oc" /usr/local/bin
    rm -rf "${extract_dir}"
}

function extract_installer() {
    local release_image
    local outdir

    release_image="$1"
    outdir="$2"

    extract_command openshift-baremetal-install "$1" "$2"
}

function clone_installer() {
  # Clone repo, if not already present
  if [[ ! -d $OPENSHIFT_INSTALL_PATH ]]; then
    sync_repo_and_patch go/src/github.com/openshift/installer https://github.com/openshift/installer.git
  fi
  pushd $OPENSHIFT_INSTALL_PATH
  git remote add kni https://github.com/openshift-kni/installer.git || true
  git fetch -v kni
  git checkout -b kni/4.3-ipv6-$$ kni/4.3-ipv6
  popd
}

function build_installer() {
  # Build installer
  pushd .
  cd $OPENSHIFT_INSTALL_PATH
  TAGS="libvirt baremetal" hack/build.sh
  popd
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

    # when using local mirror set pull secret to this mirror
    # also this should ensure we don't accidentally pull from upstream
    if [ ! -z "${MIRROR_IMAGES}" ]; then
        export PULL_SECRET=$(cat ${REGISTRY_CREDS})
    fi

    mkdir -p "${outdir}"
    cat > "${outdir}/install-config.yaml" << EOF
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
networking:
  networkType: ${NETWORK_TYPE}
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
    bootstrapOSImage: http://${MIRROR_IP}/images/${MACHINE_OS_BOOTSTRAP_IMAGE_NAME}?sha256=${MACHINE_OS_BOOTSTRAP_IMAGE_UNCOMPRESSED_SHA256}
    clusterOSImage: http://${MIRROR_IP}/images/${MACHINE_OS_IMAGE_NAME}?sha256=${MACHINE_OS_IMAGE_SHA256}
    dnsVIP: ${DNS_VIP}
    hosts:
$(master_node_map_to_install_config $NUM_MASTERS)
$(image_mirror_config)
pullSecret: |
  $(echo $PULL_SECRET | jq -c .)
sshKey: |
  ${SSH_PUB_KEY}
EOF
}
