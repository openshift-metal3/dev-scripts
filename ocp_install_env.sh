eval "$(go env)"

export OPENSHIFT_INSTALL_DATA="$GOPATH/src/github.com/openshift/installer/data/data"
export BASE_DOMAIN=test.metalkube.org
export CLUSTER_NAME=ostest
export CLUSTER_DOMAIN="${CLUSTER_NAME}.${BASE_DOMAIN}"
export SSH_PUB_KEY="`cat $HOME/.ssh/id_rsa.pub`"
export EXTERNAL_SUBNET="192.168.111.0/24"

# Not used by the installer.  Used by s.sh.
export SSH_PRIV_KEY="$HOME/.ssh/id_rsa"

