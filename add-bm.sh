#!/bin/bash
# Workaround for https://github.com/metal3-io/baremetal-operator/issues/158
set -ex

source common.sh
source ocp_install_env.sh
eval "$(go env)"

export BMOPATH="$GOPATH/src/github.com/metalkube/baremetal-operator"

BMCIP="$1"
BMCUSER="$2"
BMCPASSWORD="$3"
WORKERNAME="$4"
HARDWARE="${5:-dell}"

if [ -z "$BMCIP" ]  || [ -z "$BMCUSER" ] || [ -z "$BMCPASSWORD" ] || [ -z "$WORKERNAME" ]; then
    echo "Usage: $0 BMCIP BMCUSER BMCPASSWORD WORKERNAME HARDWARE"
    echo ""
    echo "Example: $0 1.2.3.4 'myuser' 'mypassword' 'worker-001' 'dell'"
    exit 1
fi

WORKERFILE=$(mktemp)

go run ${BMOPATH}/cmd/make-bm-worker/main.go \
  -address ${BMCIP} \
  -user ${BMCUSER} \
  -password ${BMCPASSWORD} \
  ${WORKERNAME} > ${WORKERFILE}

echo "  hardwareProfile: ${HARDWARE}" >> ${WORKERFILE}

oc --config ocp/auth/kubeconfig create -f ${WORKERFILE} -n openshift-machine-api

rm -f ${WORKERFILE}
