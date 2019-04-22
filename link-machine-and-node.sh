#!/bin/bash

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

addresses=$(oc --config ocp/auth/kubeconfig get node ${node_name} -o json | jq -c '.status.addresses')

curl -X PATCH \
     http://localhost:8001/apis/machine.openshift.io/v1beta1/namespaces/openshift-machine-api/machines/$machine_name/status \
     -H "Content-type: application/merge-patch+json" \
     -d '{"status":{"addresses":'"${addresses}"',"nodeRef":{"kind":"Node","name":"'"${node_name}"'","uid":"'"${uid}"'"}}}'
