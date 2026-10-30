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

LOGDIR="${SCRIPTDIR}/logs"
source "$SCRIPTDIR/logging.sh"
source "$SCRIPTDIR/common.sh"
source "$SCRIPTDIR/network.sh"
source "$SCRIPTDIR/ocp_install_env.sh"
source "$SCRIPTDIR/utils.sh"
source "$SCRIPTDIR/validation.sh"
source "$SCRIPTDIR/agent/common.sh"

early_deploy_validation

function approve_csrs() {
  timeout=$((30*60))
  elapsed=0
  while (( elapsed < timeout )); do
    pending_csrs=$(oc get csr | grep Pending) || true
    if [[ -n "${pending_csrs}" ]]; then
      echo "Approving CSRs: $pending_csrs"
      echo "$pending_csrs" | cut -d ' ' -f 1 | xargs oc adm certificate approve
    fi
    elapsed=$((elapsed + 10))
    sleep 10
  done
}

# not required in case no additional workers were defined
if [ "${NUM_EXTRA_WORKERS:-0}" -eq 0 ]; then
  exit 0
fi

# oc node-image commands are supported only in 4.17+
if is_lower_version "$(openshift_version "${OCP_DIR}")" "4.17" ; then
  echo "Skipping extraworker add nodes step"
  exit 0
fi

case "${AGENT_E2E_TEST_BOOT_MODE}" in
  "ISO" )
    ISO_PATH="$OCP_DIR/add-node/node.$(uname -m).iso"

    # Only regenerate the ISO if at least one VM still needs sdc attached.
    need_iso=false
    for (( n=0; n < NUM_EXTRA_WORKERS; n++ )); do
        vm="${CLUSTER_NAME}_extraworker_${n}"
        if ! sudo virsh domblklist "$vm" | grep -q "sdc"; then
            need_iso=true
            break
        fi
    done

    if [ "$need_iso" = true ]; then
        rm -f "$OCP_DIR/add-node/.openshift_install_state.json"
        rm -f "$ISO_PATH"
        oc adm node-image create --dir "$OCP_DIR/add-node/" --registry-config "${PULL_SECRET_FILE}"
    fi

    for (( n=0; n < NUM_EXTRA_WORKERS; n++ )); do
        vm="${CLUSTER_NAME}_extraworker_${n}"
        state=$(sudo virsh domstate "$vm")

        if [ "$state" = "running" ]; then
            echo "$vm already running, skipping"
            continue
        fi

        if ! sudo virsh domblklist "$vm" | grep -q "sdc"; then
            sudo virt-xml "$vm" --add-device --disk "${ISO_PATH},device=cdrom,target.dev=sdc"
            sudo virt-xml "$vm" --edit target=sda --disk="boot_order=1"
            sudo virt-xml "$vm" --edit target=sdc --disk="boot_order=2"
        fi

        sudo virsh start "$vm"
    done
    ;;

  "PXE" )
    if [ -f "$OCP_DIR/add-node/node.iso" ]; then
      rm -f "$OCP_DIR/add-node/node.iso"
    fi
    if [ -f "$OCP_DIR/add-node/.openshift_install_state.json" ]; then
      rm -f "$OCP_DIR/add-node/.openshift_install_state.json"
    fi

    oc adm node-image create --pxe --dir "$OCP_DIR/add-node/" --registry-config "${PULL_SECRET_FILE}"
    # Copy the generated PXE artifacts in the tftp server location
    # The local http server should be running and was started by
    # day 1 installtion.
    cp "$OCP_DIR"/add-node/boot-artifacts/* "${BOOT_SERVER_DIR}"

    agent_pxe_boot extraworker "$NUM_EXTRA_WORKERS"
    ;;
esac

# Disable verbose command logging (-x) for approve_csrs function.
# "set -e" is disabled because pending CSR checks can result in non-zero exit code
# if there are no CSRs currently pending. This would lead the function to exit
# before timeout is reached.
set +ex
approve_csrs &
approve_csrs_pid=$!
trap 'echo "Stopping approve csrs"; kill -TERM ${approve_csrs_pid} 2>/dev/null || true; exit; echo "Done"' INT EXIT TERM
set -ex

# shellcheck source=/dev/null
source "${SCRIPTDIR}/${OCP_DIR}/add-node/extra-workers.env"
EXTRA_WORKERS_IPS="${EXTRA_WORKERS_IPS%% }"
oc adm node-image monitor --ip-addresses "${EXTRA_WORKERS_IPS// /,}" --registry-config "${PULL_SECRET_FILE}"
