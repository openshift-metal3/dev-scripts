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
        echo "Skipping worker $machine_name because it should have inspection data to link automatically"
        continue
    fi
    $SCRIPTDIR/link-machine-and-node.sh "$machine_name" "$node"
done
