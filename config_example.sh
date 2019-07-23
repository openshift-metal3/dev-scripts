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

# Configure custom ntp servers if needed
#export NTP_SERVERS="00.my.internal.ntp.server.com;01.other.ntp.server.com"

# Uncomment to use a custom cluster-api-provider-baremetal image. The CAPBM
# image must be based on the openshift-origin version of the CAPBM from
# https://github.com/openshift/cluster-api-provider-baremetal in order to match
# the machine-api-operator.
# Setting this will also result in running the openshift-origin version of the
# machine-api-operator, rather than the one managed by the CVO.
#export CAPBM_IMAGE_SOURCE="quay.io/openshift/origin-baremetal-machine-controllers:4.2"

# Uncomment to use a custom build of the machine-api-operator running locally
#export USE_CUSTOM_MAO=true
