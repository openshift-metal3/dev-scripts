eval "$(go env)"

export OPENSHIFT_INSTALL_DATA="$GOPATH/src/github.com/openshift/installer/data/data"
export BASE_DOMAIN=test.metalkube.org
export CLUSTER_NAME=ostest
export CLUSTER_DOMAIN="${CLUSTER_NAME}.${BASE_DOMAIN}"
export SSH_PUB_KEY="`cat $HOME/.ssh/id_rsa.pub`"

# Not used by the installer.  Used by s.sh.
export SSH_PRIV_KEY="$HOME/.ssh/id_rsa"

# Temporary workaround pending merge of https://github.com/openshift/machine-api-operator/pull/246
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="quay.io/vrutkovs/kni-release:mar14"

function generate_ocp_install_config() {
    local outdir

    outdir="$1"

    cat > "${outdir}/install-config.yaml" << EOF
apiVersion: v1beta3
baseDomain: ${BASE_DOMAIN}
metadata:
  name: ${CLUSTER_NAME}
platform:
  baremetal: {}
pullSecret: |
  ${PULL_SECRET}
sshKey: |
  ${SSH_PUB_KEY}
EOF
}
