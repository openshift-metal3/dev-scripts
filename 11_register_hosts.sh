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

oc --config ocp/auth/kubeconfig apply -f $SCRIPTDIR/ocp/master_crs.yaml --namespace=openshift-machine-api

# Check if file exists
[ -s "$SCRIPTDIR/ocp/worker_crs.yaml" ] || exit 0

oc --config ocp/auth/kubeconfig apply -f $SCRIPTDIR/ocp/worker_crs.yaml --namespace=openshift-machine-api

# We automate waiting for a worker to come up and adding IPs to it for the
# default virt configuration.  This is a helpful step for the common dev setup,
# and it also runs in CI. For any other env, we just skip this, because we
# can't automatically figure out the mapping between Machines and Nodes in
# other cases, and must rely on running the link-machine-and-node.sh manually.

if [ "${NODES_PLATFORM}" != "libvirt" ] || [ "$(list_workers | wc -l)" != "1" ]; then
    exit 0
fi

wait_for_worker() {
    worker=$1
    echo "Waiting for worker $worker to appear ..."
    while [ "$(oc get nodes | grep $worker)" = "" ]; do sleep 5; done
    TIMEOUT_MINUTES=15
    echo "$worker registered, waiting $TIMEOUT_MINUTES minutes for Ready condition ..."
    oc wait node/$worker --for=condition=Ready --timeout=$[${TIMEOUT_MINUTES} * 60]s
}

wait_for_worker worker-0

# Ensures IPs get set on the worker Machine
# Run only with single worker deployments as a workaround for issue #421
if [ "$(list_workers | wc -l)" == 1 ]; then
    ./add-machine-ips.sh
fi
