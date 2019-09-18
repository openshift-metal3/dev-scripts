#!/usr/bin/bash

set -ex

source common.sh
source ocp_install_env.sh
source logging.sh

eval "$(go env)"

function list_master() {
    # Includes -machine and -machine-namespace
    cat $NODES_FILE | \
        jq '.nodes[] | select(.name | contains("openshift-master-2")) | {
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
function make_bm_nodes() {
    # Does not include -machine or -machine-namespace
    while read name address user password mac; do
        go run $SCRIPTDIR/make-bm-node/main.go \
           -address "$address" \
           -password "$password" \
           -user "$user" \
           -boot-mac "$mac" \
           "$name"
    done
}

list_master | make_bm_nodes | tee $SCRIPTDIR/ocp/master_cr.yaml
# FIXME we probably need profile matching to avoid accidentally mixing up master/worker
# nodes but in the case where there are exactly 3 master nodes and zero workers, that's OK
#list_workers | make_bm_nodes | tee $SCRIPTDIR/ocp/worker_crs.yaml
if test ${NUM_WORKERS} -gt 0 ; then
    # TODO - remove this once we set worker replicas to ${NUM_WORKERS} in
    # install-config, which will be after the machine-api-operator can deploy the
    # baremetal-operator
    oc scale machineset -n openshift-machine-api ${CLUSTER_NAME}-worker-0 --replicas=${NUM_WORKERS}
fi

# Run the fix_certs.sh script periodically as a workaround for
# https://github.com/openshift-metalkube/dev-scripts/issues/260
sudo systemd-run --on-active=30s --on-unit-active=1m --unit=fix_certs.service $(dirname $0)/fix_certs.sh

# Check if file exists
#[ -s "$SCRIPTDIR/ocp/worker_crs.yaml" ] || exit 0

#oc --config ocp/auth/kubeconfig apply -f $SCRIPTDIR/ocp/worker_crs.yaml --namespace=openshift-machine-api
oc --config ocp/auth/kubeconfig apply -f $SCRIPTDIR/ocp/master_cr.yaml --namespace=openshift-machine-api
oc --config ocp/auth/kubeconfig apply -f $SCRIPTDIR/master3.yaml

# Wait for master-2 etcd pod to show up
while ! oc --config ocp/auth/kubeconfig get pods -n openshift-etcd | grep master-2; do sleep 10; done
sleep 60 # FIXME - we get errors if running directly after the etcd pod comes up
# Run fix_etcd.sh
$SCRIPTDIR/fix_etcd.sh
oc --config ocp/auth/kubeconfig get pods -n openshift-etcd
oc --config ocp/auth/kubeconfi get nodes

