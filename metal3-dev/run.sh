#!/bin/bash -xe

bmo_path=$GOPATH/src/github.com/metal3-io/baremetal-operator
if [ ! -d $bmo_path ]; then
    echo "Did not find $bmo_path"
    exit 1
fi

source $(dirname $(dirname $0))/utils.sh

# Set some variables the operator expects to have in order to work
export OPERATOR_NAME=baremetal-operator
export DEPLOY_KERNEL_URL=http://172.22.0.3/images/ironic-python-agent.kernel
export DEPLOY_RAMDISK_URL=http://172.22.0.3/images/ironic-python-agent.initramfs
export IRONIC_ENDPOINT=http://172.22.0.3:6385/v1/
export IRONIC_INSPECTOR_ENDPOINT=http://172.22.0.3:5050/v1/

# Launch the deployment with the support services
oc apply -f $(dirname $0)/deployment.yaml -n openshift-machine-api

# Wait for the ironic service to be available
wait_for_json ironic $IRONIC_ENDPOINT 120 -H "Accept: application/json" -H "Content-Type: application/json"

cd $bmo_path

operator-sdk up local \
		     --namespace=openshift-machine-api \
		     --operator-flags="-dev"
