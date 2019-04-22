#!/usr/bin/bash

set -ex

source common.sh
source ocp_install_env.sh
eval "$(go env)"

# Get the latest bits for baremetal-operator
export BMOPATH="$GOPATH/src/github.com/metalkube/baremetal-operator"

function list_masters() {
    cat $MASTER_NODES_FILE | \
        jq '.nodes[] | {
           name,
           driver,
           address:.driver_info.ipmi_address,
           port:.driver_info.ipmi_port,
           user:.driver_info.ipmi_username,
           password:.driver_info.ipmi_password,
           mac: .ports[0].address
           } |
           .name + " " +
           .driver + "://" + .address + (if .port then ":" + .port else "" end) + " " +
           .user + " " + .password + " " + .mac' \
        | sed 's/"//g'
}

# Register the masters linked to their respective Machine objects.
function make_bm_masters() {
    while read name address user password mac; do
        go run $SCRIPTDIR/make-bm-worker/main.go \
           -address "$address" \
           -password "$password" \
           -user "$user" \
           -machine-namespace openshift-machine-api \
           -machine  "$(echo $name | sed s/openshift/${CLUSTER_NAME}/)" \
           -boot-mac "$mac" \
           "$name"
    done
}

function list_workers() {
    # Includes -machine and -machine-namespace
    cat $NODES_FILE | \
        jq '.nodes[] | select(.name | contains("worker")) | {
           name,
           driver,
           address:.driver_info.ipmi_address,
           port:.driver_info.ipmi_port,
           user:.driver_info.ipmi_username,
           password:.driver_info.ipmi_password,
           mac: .ports[0].address
           } |
           .name + " " +
           .driver + "://" + .address + (if .port then ":" + .port else "" end)  + " " +
           .user + " " + .password + " " + .mac' \
       | sed 's/"//g'
}

# Register the workers without a machine reference so they are
# available for provisioning.
function make_bm_workers() {
    # Does not include -machine or -machine-namespace
    while read name address user password mac; do
        go run $SCRIPTDIR/make-bm-worker/main.go \
           -address "$address" \
           -password "$password" \
           -user "$user" \
           -boot-mac "$mac" \
           "$name"
    done
}

list_masters | make_bm_masters | tee $SCRIPTDIR/ocp/master_crs.yaml

list_workers | make_bm_workers | tee $SCRIPTDIR/ocp/worker_crs.yaml

oc --config ocp/auth/kubeconfig apply -f $SCRIPTDIR/ocp/master_crs.yaml --namespace=openshift-machine-api

# Check if file exists
[ -s "$SCRIPTDIR/ocp/worker_crs.yaml" ] || exit 0

oc --config ocp/auth/kubeconfig apply -f $SCRIPTDIR/ocp/worker_crs.yaml --namespace=openshift-machine-api

wait_for_worker() {
    worker=$1
    echo "Waiting for worker $worker to appear ..."
    while [ "$(oc get nodes | grep $worker)" = "" ]; do sleep 5; done
    echo "$worker registered, waiting for Ready condition ..."
    oc wait node/$worker --for=condition=Ready --timeout=90s
}

wait_for_worker worker-0

# Ensures IPs get set on the worker Machine
./add-machine-ips.sh
