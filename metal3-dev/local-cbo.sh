#!/bin/bash -xe

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR=${SCRIPTDIR}/logs
source $SCRIPTDIR/logging.sh

source $SCRIPTDIR/common.sh
source $SCRIPTDIR/utils.sh

# Stop already running CBO.
pushd $SCRIPTDIR
$SCRIPTDIR/stop-cbo.sh

CBO_LOCAL_IMAGE_PATH="/etc/cluster-baremetal-operator/images"

# Copy cbo-images.json into the CBO_LOCAL_IMAGE_PATH to run CBO locally. 
# CBO needs image.json file in this path.
if [[ ! -f "${CBO_LOCAL_IMAGE_PATH}/images.json" ]]; then
    sudo mkdir -p $CBO_LOCAL_IMAGE_PATH
    sudo cp ${OCP_DIR}/cbo-images.json ${CBO_LOCAL_IMAGE_PATH}/images.json
fi

popd

cbo_path=$GOPATH/src/github.com/openshift/cluster-baremetal-operator
if [ ! -d $cbo_path ]; then
    echo "Did not find $cbo_path" 1>&2
    exit 1
fi

# Run the operator
cd $cbo_path

export RUN_NAMESPACE=openshift-machine-api
oc apply -f manifests/0000_31_cluster-baremetal-operator_01_images.configmap.yaml
oc apply -f manifests/0000_31_cluster-baremetal-operator_02_metal3provisioning.crd.yaml
oc apply -f manifests/0000_31_cluster-baremetal-operator_03_baremetalhost.crd.yaml
oc apply -f manifests/0000_31_cluster-baremetal-operator_04_serviceaccount.yaml
oc apply -f manifests/0000_31_cluster-baremetal-operator_05_rbac.yaml
oc apply -f manifests/0000_31_cluster-baremetal-operator_07_clusteroperator.cr.yaml
make run

