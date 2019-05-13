eval "$(go env)"

export OPENSHIFT_INSTALL_DATA="$GOPATH/src/github.com/openshift-metalkube/kni-installer/data/data"
export BASE_DOMAIN=${BASE_DOMAIN:-test.metalkube.org}
export CLUSTER_NAME=${CLUSTER_NAME:-ostest}
export CLUSTER_DOMAIN="${CLUSTER_NAME}.${BASE_DOMAIN}"
export SSH_PUB_KEY="`cat $HOME/.ssh/id_rsa.pub`"
export EXTERNAL_SUBNET="192.168.111.0/24"

#
# See https://origin-release.svc.ci.openshift.org/ for release details
#
# The release we default to here is pinned and known to work with our current
# version of kni-installer.
#
export OPENSHIFT_RELEASE_IMAGE="registry.svc.ci.openshift.org/markmc/release:4.0.0-0.ci-2019-04-17-133604-kni"

function generate_ocp_install_config() {
    local outdir

    outdir="$1"

    cat > "${outdir}/install-config.yaml" << EOF
apiVersion: v1beta4
baseDomain: ${BASE_DOMAIN}
metadata:
  name: ${CLUSTER_NAME}
compute:
- name: worker
  replicas: ${NUM_WORKERS}
controlPlane:
  name: master
  replicas: ${NUM_MASTERS}
platform:
  baremetal:
    nodes:
$(master_node_map_to_install_config $NUM_MASTERS)
    master_configuration:
      image_source: "http://172.22.0.1/images/$RHCOS_IMAGE_FILENAME_LATEST"
      image_checksum: $(curl http://172.22.0.1/images/$RHCOS_IMAGE_FILENAME_LATEST.md5sum)
      root_gb: 25
pullSecret: |
  ${PULL_SECRET}
sshKey: |
  ${SSH_PUB_KEY}
EOF
}
