#!/bin/bash -xe

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR=${SCRIPTDIR}/logs
source $SCRIPTDIR/logging.sh

source $SCRIPTDIR/common.sh
source $SCRIPTDIR/utils.sh

if ! which operator-sdk 2>&1 >/dev/null ; then
    echo "Did not find operator-sdk." 1>&2
    echo "Install it following the instructions from the baremetal-operator repository." 1>&2
    exit 1
fi

if ! which yq 2>&1 >/dev/null ; then
    echo "Did not find yq" 1>&2
    echo "Install with: pip3 install --user yq" 1>&2
    exit 1
fi

bmo_path=$GOPATH/src/github.com/metal3-io/baremetal-operator
if [ ! -d $bmo_path ]; then
    echo "Did not find $bmo_path" 1>&2
    exit 1
fi

# Stop the machine-api-operator so it does not try to fix the
# deployment we are going to change.
$SCRIPTDIR/stop-mao.sh

OUTDIR=${OCP_DIR}/metal3-dev
mkdir -p $OUTDIR

# Scale the existing deployment down.
oc scale deployment -n openshift-machine-api --replicas=0 metal3
if oc get pod -o name -n openshift-machine-api | grep -v metal3-development | grep -q metal3; then
    metal3pods=$(oc get pod -o name -n openshift-machine-api | grep -v metal3-development | grep metal3)
    oc wait --for=delete -n openshift-machine-api $metal3pods || true
fi

# Save a copy of the full deployment as input
oc get deployment -n openshift-machine-api -o yaml metal3 > $OUTDIR/bmo-deployment-full.yaml

# Extract the containers list, skipping the bmo
cat $OUTDIR/bmo-deployment-full.yaml \
    | yq -Y '.spec.template.spec.containers | map(select( .command[0] != "/baremetal-operator"))' \
         > $OUTDIR/bmo-deployment-dev-containers.yaml

# Get a stripped down version of the deployment
cat $OUTDIR/bmo-deployment-full.yaml \
    | yq -Y 'del(.spec.template.spec.containers) | del(.status) | del(.metadata.annotations) | del(.metadata.selfLink) | del(.metadata.uid) | del(.metadata.resourceVersion) | del(.metadata.creationTimestamp) | del(.metadata.generation)' \
         > $OUTDIR/bmo-deployment-dev-without-containers.yaml

# Combine the stripped down deployment with the container list
containers=$(cat $OUTDIR/bmo-deployment-dev-containers.yaml | yq '.')
cat $OUTDIR/bmo-deployment-dev-without-containers.yaml \
    | yq -Y --argjson containers "$containers" \
         'setpath(["spec", "template", "spec", "containers"]; $containers) | setpath(["metadata", "name"]; "metal3-development")' \
         | yq -Y 'setpath(["spec", "replicas"]; 1)' \
         > $OUTDIR/bmo-deployment-dev.yaml

# Launch the deployment with the support services and ensure it is scaled up
oc apply -f $OUTDIR/bmo-deployment-dev.yaml -n openshift-machine-api

# Set some variables the operator expects to have in order to work
export OPERATOR_NAME=baremetal-operator

for var in IRONIC_ENDPOINT IRONIC_INSPECTOR_ENDPOINT DEPLOY_KERNEL_URL DEPLOY_RAMDISK_URL; do
    export "$var"=$(cat $OUTDIR/bmo-deployment-full.yaml | yq -r ".spec.template.spec.containers[0].env | map(select( .name == \""${var}"\"))[0].value")
done

# Wait for the ironic service to be available
wait_for_json ironic "$IRONIC_ENDPOINT" 300 \
              -H "Accept: application/json" -H "Content-Type: application/json"

# Run the operator
cd $bmo_path

# Use our local verison of the CRD, in case it is newer than the one
# in the cluster now.
oc apply -f deploy/crds/metal3.io_baremetalhosts_crd.yaml

export RUN_NAMESPACE=openshift-machine-api
make -e run
