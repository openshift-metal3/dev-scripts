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
# Lifecycle phases:
#   1. Preflight  – inspect every VM before touching any
#   2. Prepare    – generate ISO/PXE artifacts (once)
#   3. Attach     – attach ISO + set boot order + start stopped VMs
#   4. Monitor    – approve CSRs and run node-image monitor
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

CDROM_TARGET="sdc"

# ---- helper functions ------------------------------------------------

function vm_name() {
  echo "${CLUSTER_NAME}_extraworker_${1}"
}

function vm_state() {
  sudo virsh domstate "$1" 2>/dev/null || echo "unknown"
}

# Resolve a path to its canonical absolute form.
# Works when the final component does not yet exist (pre-generation).
function canonical_path() {
  local path="$1"
  if [ -e "$path" ]; then
    readlink -f "$path"
    return
  fi
  local dir base
  dir=$(dirname "$path")
  base=$(basename "$path")
  if [ -d "$dir" ]; then
    echo "$(readlink -f "$dir")/$base"
  else
    readlink -m "$path"
  fi
}

# Inspect the disk at CDROM_TARGET for a VM definition.
#
# Arguments:
#   $1 - VM name
#   $2 - virsh dumpxml flags (empty for active/default, "--inactive" for
#        persistent config)
#
# Sets globals:
#   INSPECT_RESULT - one of:
#     no_target          no disk at CDROM_TARGET
#     empty_cdrom        cdrom device present, no media loaded
#     matching_cdrom     cdrom with the expected ISO
#     conflicting_cdrom  cdrom with a different ISO
#     not_cdrom          a non-cdrom disk occupies CDROM_TARGET
#     inspect_error      could not read or parse VM XML
#   INSPECT_SOURCE - the source file path (if any), or diagnostic text on error
function inspect_vm_disk() {
  local vm="$1"
  local flags="${2:-}"

  INSPECT_RESULT=""
  INSPECT_SOURCE=""

  local xml
  # shellcheck disable=SC2086
  if ! xml=$(sudo virsh dumpxml $flags "$vm" 2>&1); then
    INSPECT_RESULT="inspect_error"
    INSPECT_SOURCE="virsh dumpxml failed: $xml"
    return
  fi

  local target_count
  if ! target_count=$(echo "$xml" | xmllint --xpath \
       "count(//disk/target[@dev='${CDROM_TARGET}'])" - 2>&1); then
    INSPECT_RESULT="inspect_error"
    INSPECT_SOURCE="xmllint failed to evaluate target count: $target_count"
    return
  fi

  if [ "$target_count" = "0" ]; then
    INSPECT_RESULT="no_target"
    return
  fi

  local device_type
  if ! device_type=$(echo "$xml" | xmllint --xpath \
       "string(//disk[target/@dev='${CDROM_TARGET}']/@device)" - 2>&1); then
    INSPECT_RESULT="inspect_error"
    INSPECT_SOURCE="failed to read device type for ${CDROM_TARGET}: $device_type"
    return
  fi

  if [ "$device_type" != "cdrom" ]; then
    INSPECT_RESULT="not_cdrom"
    INSPECT_SOURCE="$device_type"
    return
  fi

  local source_file
  if ! source_file=$(echo "$xml" | xmllint --xpath \
       "string(//disk[target/@dev='${CDROM_TARGET}']/source/@file)" - 2>&1); then
    INSPECT_RESULT="inspect_error"
    INSPECT_SOURCE="failed to read source for ${CDROM_TARGET}: $source_file"
    return
  fi

  if [ -z "$source_file" ]; then
    INSPECT_RESULT="empty_cdrom"
    return
  fi

  INSPECT_SOURCE="$source_file"

  local canon_source canon_expected
  canon_source=$(canonical_path "$source_file")
  canon_expected=$(canonical_path "$EXPECTED_ISO")

  if [ "$canon_source" = "$canon_expected" ]; then
    INSPECT_RESULT="matching_cdrom"
  else
    INSPECT_RESULT="conflicting_cdrom"
  fi
}

# ---- approve_csrs ----------------------------------------------------

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

# ---- early exits -----------------------------------------------------

if [ "${NUM_EXTRA_WORKERS:-0}" -eq 0 ]; then
  exit 0
fi

if is_lower_version "$(openshift_version "${OCP_DIR}")" "4.17" ; then
  echo "Skipping extraworker add nodes step"
  exit 0
fi

# ---- PXE path (unchanged) -------------------------------------------

if [ "${AGENT_E2E_TEST_BOOT_MODE}" = "PXE" ]; then
  if [ -f "$OCP_DIR/add-node/node.iso" ]; then
    rm -f "$OCP_DIR/add-node/node.iso"
  fi
  if [ -f "$OCP_DIR/add-node/.openshift_install_state.json" ]; then
    rm -f "$OCP_DIR/add-node/.openshift_install_state.json"
  fi

  oc adm node-image create --pxe --dir "$OCP_DIR/add-node/" --registry-config "${PULL_SECRET_FILE}"
  cp "$OCP_DIR"/add-node/boot-artifacts/* "${BOOT_SERVER_DIR}"
  agent_pxe_boot extraworker "$NUM_EXTRA_WORKERS"

  set +ex
  approve_csrs &
  approve_csrs_pid=$!
  trap 'echo "Stopping approve csrs"; kill -TERM ${approve_csrs_pid} 2>/dev/null || true; exit; echo "Done"' INT EXIT TERM
  set -ex

  # shellcheck source=/dev/null
  source "${SCRIPTDIR}/${OCP_DIR}/add-node/extra-workers.env"
  EXTRA_WORKERS_IPS="${EXTRA_WORKERS_IPS%% }"
  oc adm node-image monitor --ip-addresses "${EXTRA_WORKERS_IPS// /,}" --registry-config "${PULL_SECRET_FILE}"
  exit 0
fi

# ---- ISO path --------------------------------------------------------

ADD_NODE_DIR="$OCP_DIR/add-node"
EXPECTED_ISO=$(canonical_path "$ADD_NODE_DIR/node.$(uname -m).iso")

# Phase 1: Preflight – inspect every VM before modifying any.
declare -a VM_NAMES=()
declare -a VM_STATES=()
declare -a VM_ACTIONS=()

need_iso_generation=false
has_running=false
has_stopped=false

for (( n=0; n < NUM_EXTRA_WORKERS; n++ )); do
  name=$(vm_name "$n")
  state=$(vm_state "$name")

  VM_NAMES+=("$name")
  VM_STATES+=("$state")

  state_trimmed=$(echo "$state" | xargs)

  inspect_vm_disk "$name" ""
  disk_result="$INSPECT_RESULT"
  disk_source="$INSPECT_SOURCE"

  case "${state_trimmed}" in
    "shut off")
      has_stopped=true
      case "$disk_result" in
        "no_target")
          VM_ACTIONS+=("attach")
          need_iso_generation=true
          ;;
        "matching_cdrom")
          VM_ACTIONS+=("reuse")
          ;;
        "empty_cdrom")
          echo "ERROR: VM $name has an empty cdrom at ${CDROM_TARGET} (no media loaded)."
          echo "Detach it before retrying:"
          echo "  sudo virt-xml $name --remove-device --disk target=${CDROM_TARGET}"
          exit 1
          ;;
        "conflicting_cdrom")
          echo "ERROR: VM $name has ${CDROM_TARGET} attached to unexpected ISO:"
          echo "  attached: $disk_source"
          echo "  expected: $EXPECTED_ISO"
          echo "Detach it before retrying:"
          echo "  sudo virt-xml $name --remove-device --disk target=${CDROM_TARGET}"
          exit 1
          ;;
        "not_cdrom")
          echo "ERROR: VM $name has a non-cdrom disk at ${CDROM_TARGET} (type: $disk_source)."
          echo "Resolve this conflict before retrying."
          exit 1
          ;;
        "inspect_error")
          echo "ERROR: Could not inspect VM $name: $disk_source"
          echo "Verify the VM exists and libvirt is accessible."
          exit 1
          ;;
      esac
      ;;

    "running")
      has_running=true

      # For running VMs also verify the persistent config agrees with the
      # active config.  A mismatch indicates a partially applied change
      # (e.g. hotplug failed after virt-xml modified the persistent def).
      case "$disk_result" in
        "matching_cdrom")
          inspect_vm_disk "$name" "--inactive"
          if [ "$INSPECT_RESULT" != "matching_cdrom" ]; then
            echo "ERROR: VM $name active config has the expected ${CDROM_TARGET},"
            echo "but its persistent definition disagrees (${INSPECT_RESULT})."
            echo "This indicates a partially applied change. Stop the VM and retry:"
            echo "  sudo virsh shutdown $name"
            exit 1
          fi
          VM_ACTIONS+=("monitor")
          ;;
        "empty_cdrom")
          echo "ERROR: VM $name is running with an empty cdrom at ${CDROM_TARGET}."
          echo "Cannot determine installation state. Stop the VM and investigate:"
          echo "  sudo virsh shutdown $name"
          exit 1
          ;;
        "conflicting_cdrom")
          echo "ERROR: VM $name is running with ${CDROM_TARGET} attached to unexpected ISO:"
          echo "  attached: $disk_source"
          echo "  expected: $EXPECTED_ISO"
          echo "Stop the VM before correcting:"
          echo "  sudo virsh shutdown $name"
          exit 1
          ;;
        "no_target")
          echo "ERROR: VM $name is running but has no ${CDROM_TARGET} attached."
          echo "Cannot determine installation state. Stop the VM and investigate:"
          echo "  sudo virsh shutdown $name"
          exit 1
          ;;
        "not_cdrom")
          echo "ERROR: VM $name is running with a non-cdrom disk at ${CDROM_TARGET} (type: $disk_source)."
          echo "Stop the VM and resolve this conflict:"
          echo "  sudo virsh shutdown $name"
          exit 1
          ;;
        "inspect_error")
          echo "ERROR: Could not inspect running VM $name: $disk_source"
          echo "Verify the VM exists and libvirt is accessible."
          exit 1
          ;;
      esac
      ;;

    *)
      echo "ERROR: VM $name is in unexpected state: $state_trimmed"
      echo "Resolve the VM state before retrying."
      exit 1
      ;;
  esac
done

# Reject mixed stopped/running workers sharing the same ISO.
if [ "$has_running" = true ] && [ "$has_stopped" = true ]; then
  echo "ERROR: Mixed VM states detected – some extra workers are running while others are stopped."
  echo "This combination is unsafe: regenerating the ISO could corrupt running installations,"
  echo "and skipping generation may leave stopped VMs without a valid ISO."
  echo ""
  echo "VM states:"
  for (( n=0; n < ${#VM_NAMES[@]}; n++ )); do
    echo "  ${VM_NAMES[$n]}: $(echo "${VM_STATES[$n]}" | xargs) (action: ${VM_ACTIONS[$n]})"
  done
  echo ""
  echo "Mixed running/stopped extra workers are not supported by this retry path."
  echo "No ISO or VM changes have been made."
  echo "Check which workers have already joined the cluster before proceeding."
  echo "Preserve joined workers; do not delete nodes or reset disks to satisfy"
  echo "this preflight check."
  exit 1
fi

# Phase 2: Prepare artifacts – generate ISO only when needed.
if [ "$need_iso_generation" = true ]; then
  if [ -f "$ADD_NODE_DIR/.openshift_install_state.json" ]; then
    rm -f "$ADD_NODE_DIR/.openshift_install_state.json"
  fi
  if [ -f "$EXPECTED_ISO" ]; then
    rm -f "$EXPECTED_ISO"
  fi

  oc adm node-image create --dir "$ADD_NODE_DIR/" --registry-config "${PULL_SECRET_FILE}"

  if [ ! -f "$EXPECTED_ISO" ]; then
    echo "ERROR: Expected ISO not found after generation: $EXPECTED_ISO"
    exit 1
  fi
fi

# Phase 3: Attach/start – process each VM according to its preflight action.
for (( n=0; n < ${#VM_NAMES[@]}; n++ )); do
  name="${VM_NAMES[$n]}"
  action="${VM_ACTIONS[$n]}"

  case "$action" in
    "attach")
      sudo virt-xml "$name" --add-device --disk "${EXPECTED_ISO},device=cdrom,target.dev=${CDROM_TARGET}"
      sudo virt-xml "$name" --edit target=sda --disk="boot_order=1"
      sudo virt-xml "$name" --edit target=${CDROM_TARGET} --disk="boot_order=2" --start
      ;;
    "reuse")
      if [ ! -f "$EXPECTED_ISO" ]; then
        echo "ERROR: VM $name has ${CDROM_TARGET} attached but the ISO file is missing: $EXPECTED_ISO"
        echo "Detach the stale reference and retry to regenerate:"
        echo "  sudo virt-xml $name --remove-device --disk target=${CDROM_TARGET}"
        exit 1
      fi
      echo "Reusing existing ${CDROM_TARGET} attachment on $name"
      sudo virt-xml "$name" --edit target=sda --disk="boot_order=1"
      sudo virt-xml "$name" --edit target=${CDROM_TARGET} --disk="boot_order=2" --start
      ;;
    "monitor")
      echo "VM $name is already running – will resume monitoring"
      ;;
  esac
done

# Phase 4: Monitor – approve CSRs and watch installation progress.
set +ex
approve_csrs &
approve_csrs_pid=$!
trap 'echo "Stopping approve csrs"; kill -TERM ${approve_csrs_pid} 2>/dev/null || true; exit; echo "Done"' INT EXIT TERM
set -ex

# shellcheck source=/dev/null
source "${SCRIPTDIR}/${OCP_DIR}/add-node/extra-workers.env"
EXTRA_WORKERS_IPS="${EXTRA_WORKERS_IPS%% }"
oc adm node-image monitor --ip-addresses "${EXTRA_WORKERS_IPS// /,}" --registry-config "${PULL_SECRET_FILE}"
