#!/bin/bash

source utils.sh

set -x
set -e

machine="$1"
node="$2"

if [ -z "$machine" -o -z "$node" ]; then
    echo "Usage: $0 MACHINE NODE"
    exit 1
fi

uid=$(echo $node | cut -f1 -d':')
node_name=$(echo $node | cut -f2 -d':')

# BEGIN Hack #260
# Hack workaround for openshift-metalkube/dev-scripts#260 until it's done automatically
# Also see https://github.com/metalkube/cluster-api-provider-baremetal/issues/49
oc --config ocp/auth/kubeconfig proxy &
proxy_pid=$!

PROXY_API_PATH="http://localhost:8001/apis/machine.openshift.io/v1beta1/namespaces/openshift-machine-api/machines"
wait_for_json oc_proxy "${PROXY_API_PATH}" 10 -H "Accept: application/json" -H "Content-Type: application/json"

addresses=$(oc --config ocp/auth/kubeconfig get node ${node_name} -o json | jq -c '.status.addresses')

curl -X PATCH \
     ${PROXY_API_PATH}/${machine}/status \
     -H "Content-type: application/merge-patch+json" \
     -d '{"status":{"addresses":'"${addresses}"',"nodeRef":{"kind":"Node","name":"'"${node_name}"'","uid":"'"${uid}"'"}}}'

kill $proxy_pid
