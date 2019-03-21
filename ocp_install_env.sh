eval "$(go env)"

export OPENSHIFT_INSTALL_DATA="$GOPATH/src/github.com/openshift-metalkube/kni-installer/data/data"
export BASE_DOMAIN=${BASE_DOMAIN:-test.metalkube.org}
export CLUSTER_NAME=${CLUSTER_NAME:-ostest}
export CLUSTER_DOMAIN="${CLUSTER_NAME}.${BASE_DOMAIN}"
export SSH_PUB_KEY="`cat $HOME/.ssh/id_rsa.pub`"
export EXTERNAL_SUBNET="192.168.111.0/24"

# Not used by the installer.  Used by s.sh.
export SSH_PRIV_KEY="$HOME/.ssh/id_rsa"

# Temporary workaround pending merge of https://github.com/openshift/machine-api-operator/pull/246
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="registry.svc.ci.openshift.org/openshift/origin-release:v4.0"

function generate_ocp_install_config() {
    local outdir

    outdir="$1"

    PLATFORM_YAML=`jq '.nodes[0:3] | {nodes: .}' ${NODES_FILE} | python -c 'import sys, yaml, json; from flatten_json import flatten; yaml.safe_dump({"platform": {"baremetal": {"nodes": flatten(json.load(sys.stdin))}}}, sys.stdout, default_flow_style=False)'`

    cat > "${outdir}/install-config.yaml" << EOF
apiVersion: v1beta3
baseDomain: ${BASE_DOMAIN}
metadata:
  name: ${CLUSTER_NAME}
platform:
  baremetal:
    nodes:
$(master_node_to_install_config 0)
$(master_node_to_install_config 1)
$(master_node_to_install_config 2)
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
