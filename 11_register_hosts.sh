#!/usr/bin/bash

set -ex

source common.sh
source ocp_install_env.sh
source logging.sh

eval "$(go env)"

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
           -externally-provisioned \
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

# Register the workers without a consumer reference so they are
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
# TODO - remove this once we set worker replicas to ${NUM_WORKERS} in
# install-config, which will be after the machine-api-operator can deploy the
# baremetal-operator
oc scale machineset -n openshift-machine-api ${CLUSTER_NAME}-worker-0 --replicas=${NUM_WORKERS}

oc --config ocp/auth/kubeconfig apply -f $SCRIPTDIR/ocp/master_crs.yaml --namespace=openshift-machine-api

# Check if file exists
[ -s "$SCRIPTDIR/ocp/worker_crs.yaml" ] || exit 0

oc --config ocp/auth/kubeconfig apply -f $SCRIPTDIR/ocp/worker_crs.yaml --namespace=openshift-machine-api
