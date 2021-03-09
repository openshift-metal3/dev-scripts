#!/bin/bash -xe

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR=${SCRIPTDIR}/logs
source $SCRIPTDIR/logging.sh

source $SCRIPTDIR/common.sh
source $SCRIPTDIR/utils.sh

cbo_path=$GOPATH/src/github.com/openshift/cluster-baremetal-operator
if [ ! -d $cbo_path ]; then
    echo "Did not find $cbo_path" 1>&2
    exit 1
fi

# Run the operator
cd $cbo_path

export IMAGES_JSON=${SCRIPTDIR}/${OCP_DIR}/cbo-images.json
export RUN_NAMESPACE=openshift-machine-api
oc apply -f manifests/
make run

