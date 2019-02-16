#!/bin/bash

# Get a valid pull secret (json string) from
# You can get this secret from https://cloud.openshift.com/clusters/install#pull-secret
export PULL_SECRET=''

# Uncomment to build a copy of ironic or inspector locally
#export IRONIC_INSPECTOR_IMAGE=https://github.com/metalkube/metalkube-ironic-inspector
#export IRONIC_IMAGE=https://github.com/metalkube/metalkube-ironic
