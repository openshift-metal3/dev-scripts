#!/usr/bin/env bash
#
# This scripts adds extraworker nodes to the cluster.
# The number of extraworker nodes is defined through
# NUM_EXTRA_WORKERS.
#
# The nodes can be added either through booting with
# ISO or through the network using PXE if
# AGENT_E2E_TEST_BOOT_MODE=PXE.
#
# The ISO or PXE artifacts are generated using
#   oc adm node-image create
#
# After the nodes are booted, their installation progress
# is monitored through
#   oc adm node-image monitor
#
# To remove the nodes added by this script from the
# cluster, use agent_remove_node.sh or run
#   make agent_remove_node
#

set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR=${SCRIPTDIR}/logs
source $SCRIPTDIR/logging.sh
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/network.sh
source $SCRIPTDIR/ocp_install_env.sh
source $SCRIPTDIR/utils.sh
source $SCRIPTDIR/validation.sh
source $SCRIPTDIR/agent/common.sh

early_deploy_validation

function approve_csrs() {
  # approve CSRs for up to 30 mins
  timeout=$((30*60))
  elapsed=0
  while (( elapsed < timeout )); do
    pending_csrs=$(oc get csr | grep Pending)
    if [[ ${pending_csrs} != "" ]]; then
      echo "Approving CSRs: $pending_csrs"
      echo $pending_csrs | cut -d ' ' -f 1 | xargs oc adm certificate approve
    fi
    elapsed=$((elapsed + 10))
    sleep 10
  done
}

if [ -f $OCP_DIR/add-node/node.iso ]; then
  rm -f $OCP_DIR/add-node/node.iso
fi

if [ -f $OCP_DIR/add-node/.openshift_install_state.json ]; then
  rm -f $OCP_DIR/add-node/.openshift_install_state.json
fi

case "${AGENT_E2E_TEST_BOOT_MODE}" in
  "ISO" )
    oc adm node-image create --dir $OCP_DIR/add-node/ --registry-config "${PULL_SECRET_FILE}" --loglevel=2

    for (( n=0; n<${NUM_EXTRA_WORKERS}; n++ ))
    do
        sudo virt-xml "${CLUSTER_NAME}_extraworker_${n}" --add-device --disk "$OCP_DIR/add-node//node.x86_64.iso,device=cdrom,target.dev=sdc"
        sudo virt-xml "${CLUSTER_NAME}_extraworker_${n}" --edit target=sda --disk="boot_order=1"
        sudo virt-xml "${CLUSTER_NAME}_extraworker_${n}" --edit target=sdc --disk="boot_order=2" --start
    done
    ;;

  "PXE" )
    oc adm node-image create --pxe --dir $OCP_DIR/add-node/ --registry-config "${PULL_SECRET_FILE}" --loglevel=2
    # Copy the generated PXE artifacts in the tftp server location
    # The local http server should be running and was started by
    # day 1 installtion.
    cp $OCP_DIR/add-node//boot-artifacts/* ${BOOT_SERVER_DIR}

    agent_pxe_boot extraworker $NUM_EXTRA_WORKERS
    ;;
esac

# Disable verbose command logging (-x) for approve_csrs function.
# "set -e" id is disabled because pending CSR checks can result in non-zero exit code
# if there are no CSRs currently pending. This would lead the function to exit
# before timeout is reached.
set +ex
approve_csrs &
approve_csrs_pid=$!
trap 'kill -TERM ${approve_csrs_pid}; exit' INT EXIT TERM
set -ex

source "${SCRIPTDIR}/${OCP_DIR}/add-node/extra-workers.env"
EXTRA_WORKERS_IPS="${EXTRA_WORKERS_IPS%% }"
oc adm node-image monitor --ip-addresses "${EXTRA_WORKERS_IPS// /,}" --registry-config "${PULL_SECRET_FILE}" --loglevel=2
