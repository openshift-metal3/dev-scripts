#!/bin/bash -xe

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR=${SCRIPTDIR}/logs
source $SCRIPTDIR/logging.sh

source $SCRIPTDIR/common.sh
source $SCRIPTDIR/utils.sh

CBO_PATH=${CBO_PATH:-$GOPATH/src/github.com/openshift/cluster-baremetal-operator}
if [ ! -d $CBO_PATH ]; then
    echo "Did not find $CBO_PATH" 1>&2
    exit 1
fi

# Make the TLS files available in the expected location on the present host
mkdir -p /etc/cluster-baremetal-operator/tls

oc get secret -n openshift-machine-api cluster-baremetal-operator-tls -o json \
    | jq '.data."tls.crt"' -r \
    | base64 -d > /etc/cluster-baremetal-operator/tls/tls.crt

oc get secret -n openshift-machine-api cluster-baremetal-operator-tls -o json \
    | jq '.data."tls.key"' -r \
    | base64 -d > /etc/cluster-baremetal-operator/tls/tls.key

# Run the operator
cd $CBO_PATH

export IMAGES_JSON=${SCRIPTDIR}/${OCP_DIR}/cbo-images.json
export RUN_NAMESPACE=openshift-machine-api
oc apply -f manifests/
make run

