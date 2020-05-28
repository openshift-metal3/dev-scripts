#!/bin/bash -xe

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR=${SCRIPTDIR}/logs
source $SCRIPTDIR/logging.sh

# Scale down dev deployment
oc scale deployment -n openshift-machine-api --replicas=0 metal3-development
if oc get pod -o name -n openshift-machine-api | grep -q metal3-development; then
    metal3pods=$(oc get pod -o name -n openshift-machine-api | grep metal3-development)
    oc wait --for=delete -n openshift-machine-api $metal3pods || true
fi

# Scale up regular deployment
oc scale deployment -n openshift-machine-api --replicas=1 metal3
