#!/bin/bash
set -x
set -e

source logging.sh
source utils.sh
source common.sh
source ocp_install_env.sh

# BEGIN Hack #260
# Hack workaround for openshift-metalkube/dev-scripts#260 until it's done automatically
# Also see https://github.com/metalkube/cluster-api-provider-baremetal/issues/49
oc --config ocp/auth/kubeconfig proxy &
proxy_pid=$!

for node in $(oc --config ocp/auth/kubeconfig get nodes -o template --template='{{range .items}}{{.metadata.uid}}:{{.metadata.name}}{{"\n"}}{{end}}'); do
    node_name=$(echo $node | cut -f2 -d':')
    machine_name=$CLUSTER_NAME-$node_name
    if [[ "$machine_name" == *"worker"* ]]; then
        machine_name=$(oc --config ocp/auth/kubeconfig get machines -n openshift-machine-api | grep $node_name | cut -f1 -d' ')
    fi
    uid=$(echo $node | cut -f1 -d':')
    addresses=$(oc --config ocp/auth/kubeconfig get node $node_name -o json | jq -c '.status.addresses')
    curl -X PATCH http://localhost:8001/apis/machine.openshift.io/v1beta1/namespaces/openshift-machine-api/machines/$machine_name/status -H "Content-type: application/merge-patch+json" -d '{"status":{"addresses":'"${addresses}"',"nodeRef":{"kind":"Node","name":"'"${node_name}"'","uid":"'"${uid}"'"}}}'
done

kill $proxy_pid
