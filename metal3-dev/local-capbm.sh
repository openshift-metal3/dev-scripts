#!/bin/bash -xe

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR=${SCRIPTDIR}/logs
source $SCRIPTDIR/logging.sh

source $SCRIPTDIR/common.sh
source $SCRIPTDIR/utils.sh

if ! which yq 2>&1 >/dev/null ; then
    echo "Did not find yq" 1>&2
    echo "Install with: python -m pip --user yq" 1>&2
    exit 1
fi

CAPBM_PATH=${CLUSTER_API_PROVIDER_BAREMETAL_PATH:-$GOPATH/src/github.com/openshift/cluster-api-provider-baremetal}
if [ ! -d $CAPBM_PATH ]; then
    echo "Did not find $CAPBM_PATH" 1>&2
    exit 1
fi

# Stop the machine-api-operator so it does not try to fix the
# deployment we are going to change.
$SCRIPTDIR/stop-mao.sh

OUTDIR=${OCP_DIR}/metal3-dev
mkdir -p $OUTDIR

# Scale the existing deployment down.
oc scale deployment -n openshift-machine-api --replicas=0 machine-api-controllers
if oc get pod -o name -n openshift-machine-api | grep -q machine-api-controllers; then
    pods=$(oc get pod -o name -n openshift-machine-api | grep machine-api-controllers)
    oc wait --for=delete -n openshift-machine-api $pods || true
fi

# Save a copy of the full deployment as input
oc get deployment -n openshift-machine-api -o yaml machine-api-controllers > $OUTDIR/capbm-deployment-full.yaml

# Extract the containers list, skipping the capbm
cat $OUTDIR/capbm-deployment-full.yaml \
    | yq -Y '.spec.template.spec.containers | map(select( .command[0] != "/machine-controller-manager"))' \
         > $OUTDIR/capbm-deployment-dev-containers.yaml

# Get a stripped down version of the deployment
cat $OUTDIR/capbm-deployment-full.yaml \
    | yq -Y 'del(.spec.template.spec.containers) | del(.status) | del(.metadata.annotations) | del(.metadata.selfLink) | del(.metadata.uid) | del(.metadata.resourceVersion) | del(.metadata.creationTimestamp) | del(.metadata.generation)' \
         > $OUTDIR/capbm-deployment-dev-without-containers.yaml

# Combine the stripped down deployment with the container list
containers=$(cat $OUTDIR/capbm-deployment-dev-containers.yaml | yq '.')
cat $OUTDIR/capbm-deployment-dev-without-containers.yaml \
    | yq -Y --argjson containers "$containers" \
         'setpath(["spec", "template", "spec", "containers"]; $containers) | setpath(["metadata", "name"]; "capbm-development")' \
         | yq -Y 'setpath(["spec", "replicas"]; 1)' \
         > $OUTDIR/capbm-deployment-dev.yaml

# Launch the deployment with the support services and ensure it is scaled up
oc apply -f $OUTDIR/capbm-deployment-dev.yaml -n openshift-machine-api

# Run the local capbm
cd $CAPBM_PATH

make build && ./bin/machine-controller-manager --logtostderr=true --v=3 --namespace=openshift-machine-api --health-addr ":9441"
