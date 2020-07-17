#!/bin/bash -xe

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR=${SCRIPTDIR}/logs
source $SCRIPTDIR/logging.sh

# Scale down dev deployment
oc scale deployment -n openshift-machine-api --replicas=0 capbm-development
if oc get pod -o name -n openshift-machine-api | grep -q capbm-development; then
    pods=$(oc get pod -o name -n openshift-machine-api | grep capbm-development)
    oc wait --for=delete -n openshift-machine-api $pods || true
fi

# Scale up regular deployment
oc scale deployment -n openshift-machine-api --replicas=1 machine-api-controllers
