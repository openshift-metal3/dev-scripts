#!/usr/bin/env bash
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

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

oc adm node-image create --dir "$OCP_DIR/add-node/"

for (( n=0; n<${NUM_EXTRA_WORKERS}; n++ ))
do
    sudo virt-xml "${CLUSTER_NAME}_extraworker_${n}" --add-device --disk "$OCP_DIR/add-node/node.iso,device=cdrom,target.dev=sdc"
    sudo virt-xml "${CLUSTER_NAME}_extraworker_${n}" --edit target=sda --disk="boot_order=1"
    sudo virt-xml "${CLUSTER_NAME}_extraworker_${n}" --edit target=sdc --disk="boot_order=2" --start
done

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
oc adm node-image monitor --ip-addresses "${EXTRA_WORKERS_IPS// /,}"  --kubeconfig "$OCP_DIR/auth/kubeconfig"
