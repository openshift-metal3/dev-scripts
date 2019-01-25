eval "$(go env)"

export OPENSHIFT_INSTALL_DATA="$GOPATH/src/github.com/openshift/installer/data/data"
export BASE_DOMAIN=test.metalkube.org
export CLUSTER_NAME=ostest
export PULL_SECRET='{"auths": { "quay.io": { "auth": "Y29yZW9zK3RlYzJfaWZidWdsa2VndmF0aXJyemlqZGMybnJ5ZzpWRVM0SVA0TjdSTjNROUUwMFA1Rk9NMjdSQUZNM1lIRjRYSzQ2UlJBTTFZQVdZWTdLOUFIQlM1OVBQVjhEVlla", "email": "" }}}'
export SSH_PUB_KEY="`cat $HOME/.ssh/id_rsa.pub`"

# Not used by the installer.  Used by s.sh.
export SSH_PRIV_KEY="$HOME/.ssh/id_rsa"

