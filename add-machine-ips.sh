#!/bin/bash
set -x
set -e

source logging.sh
source utils.sh
source common.sh
source ocp_install_env.sh

for node in $(oc --config ocp/auth/kubeconfig get nodes -o template --template='{{range .items}}{{.metadata.uid}}:{{.metadata.name}}{{"\n"}}{{end}}'); do
    node_name=$(echo $node | cut -f2 -d':')
    machine_name=$CLUSTER_NAME-$node_name
    if [[ "$machine_name" == *"worker"* ]]; then
        machine_name=$(oc --config ocp/auth/kubeconfig get machines -n openshift-machine-api | grep $node_name | cut -f1 -d' ')
    fi
    sleep 3
    $SCRIPTDIR/link-machine-and-node.sh "$machine_name" "$node"
done
