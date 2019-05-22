#!/bin/bash

# Get a valid pull secret (json string) from
# You can get this secret from https://cloud.openshift.com/clusters/install#pull-secret
set +x
export PULL_SECRET=''
set -x

# Uncomment to build a copy of ironic or inspector locally
#export IRONIC_INSPECTOR_IMAGE=https://github.com/metal3-io/ironic-inspector
#export IRONIC_IMAGE=https://github.com/metal3-io/ironic

# SSH key used to ssh into deployed hosts.  This must be the contents of the
# variable, not the filename. The contents of ~/.ssh/id_rsa.pub are used by
# default.
#export SSH_PUB_KEY=$(cat ~/.ssh/id_rsa.pub)
