#!/bin/bash

# Run the baremetal operator locally in "demo" mode.
#
# This script assumes that you have ~/.kube/config set up, which may
# mean copying ocp/auth/kubeconfig after running the scripts to build
# a dev environment.

set -xe

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source ${SCRIPTDIR}/../common.sh
eval $(go env)

# Set the project
oc project openshift-machine-api

# First kill off any existing deployments so there is no conflict
if oc get deployments | grep -q metal3-baremetal-operator
then
    echo "Stopping existing deployment..."
    oc delete deployment metal3-baremetal-operator
fi

cd $GOPATH/src/github.com/metal3-io/baremetal-operator

oc apply -f deploy/crds/demo-hosts.yaml

export OPERATOR_NAME=baremetal-operator

${GOPATH}/bin/operator-sdk up local \
    --namespace=openshift-machine-api \
	--operator-flags="-dev -demo-mode"
