#!/bin/bash

# This script disables the Machine API Operator deployed by the Cluster Version
# Operator and subsittutes a locally-built one. This is also a prerequisite to
# deploying a custom actuator (e.g. a custom cluster-api-provider-baremetal),
# by linking to a different quay.io image in the machine-api-operator's
# images.json file.
#
# For more details, about how this all works, see the file
# docs/custom-mao-and-capbm.md

set -e

DEV_SCRIPTS_DIR=$(realpath $(dirname $0))
KUBECONFIG="${DEV_SCRIPTS_DIR}/ocp/auth/kubeconfig"

oc --config=${KUBECONFIG} patch clusterversion version --namespace openshift-cluster-version --type merge -p '{"spec":{"overrides":[{"kind":"Deployment","name":"machine-api-operator","namespace":"openshift-machine-api","unmanaged":true}]}}'

oc --config=${KUBECONFIG} scale deployment -n openshift-machine-api --replicas=0 machine-api-operator

# This is in the instructions but doesn't seem to be required (deployment does not exist)
#oc --config=${KUBECONFIG} delete deployment -n openshift-machine-api clusterapi-manager-controllers

eval "$(go env)"
MAO_PATH="${GOPATH}/src/github.com/openshift/machine-api-operator"
IMAGES_FILE="pkg/operator/fixtures/images.json"

if [ ! -d "${MAO_PATH}" ]; then
    go get -d github.com/openshift/machine-api-operator/cmd/machine-api-operator

    pushd ${MAO_PATH}
    git checkout release-4.2

    sed -i -e 's/docker/quay/' -e 's/v4.0.0/4.2.0/' "${IMAGES_FILE}"
    if ! git diff --quiet -- "${IMAGES_FILE}"; then
        git add "${IMAGES_FILE}"
        git commit -m 'Use 4.2 images'
    fi
else
    pushd ${MAO_PATH}
fi

sudo podman run --rm -v ${MAO_PATH}:/go/src/github.com/openshift/machine-api-operator:Z -w /go/src/github.com/openshift/machine-api-operator golang:1.10 ./hack/go-build.sh machine-api-operator
popd

# A custom cluster-api-provider-baremetal image can be specified in the file
# pkg/operator/fixtures/images.json. The CAPBM image must be based on the
# openshift-origin version of the CAPBM from
# https://github.com/openshift/cluster-api-provider-baremetal

${MAO_PATH}/bin/machine-api-operator start --images-json="${MAO_PATH}/${IMAGES_FILE}" --kubeconfig="${KUBECONFIG}" --v=4
