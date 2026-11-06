#!/bin/bash
#
# Example: Adding Worker Nodes Post-Installation
#
# This script demonstrates various ways to add worker nodes
# to your cluster after deployment.
#

# NOTE: This is an example file showing different usage patterns.
# Copy and modify as needed for your use case.

set -e

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$SCRIPTDIR"

echo "=========================================="
echo "Example: Adding Workers Post-Installation"
echo "=========================================="
echo ""

# ============================================================================
# Example 1: Add a single worker with default resources
# ============================================================================
echo "Example 1: Add worker with default resources (16GB RAM, 50GB disk, 8 vCPU)"
echo ""
echo "Commands:"
echo "  ./add_worker_node.sh worker-default"
echo "  oc apply -f ocp/ostest/worker-default_bmh.yaml"
echo "  oc scale machineset \$(oc get machineset -n openshift-machine-api -o name | head -1 | cut -d/ -f2) --replicas=3 -n openshift-machine-api"
echo ""

# ============================================================================
# Example 2: Add a large worker with custom resources
# ============================================================================
echo "Example 2: Add large worker with custom resources"
echo ""
echo "Commands:"
echo "  export EXTRA_WORKER_MEMORY=32768  # 32GB RAM"
echo "  export EXTRA_WORKER_DISK=100      # 100GB disk"
echo "  export EXTRA_WORKER_VCPU=16       # 16 vCPUs"
echo "  ./add_worker_node.sh worker-large"
echo "  oc apply -f ocp/ostest/worker-large_bmh.yaml"
echo ""

# ============================================================================
# Example 3: Add multiple workers in sequence
# ============================================================================
echo "Example 3: Add multiple workers (requires running commands sequentially)"
echo ""
echo "Commands:"
echo "  # Add first worker"
echo "  ./add_worker_node.sh worker-1"
echo "  oc apply -f ocp/ostest/worker-1_bmh.yaml"
echo ""
echo "  # Add second worker"
echo "  ./add_worker_node.sh worker-2"
echo "  oc apply -f ocp/ostest/worker-2_bmh.yaml"
echo ""
echo "  # Add third worker"
echo "  ./add_worker_node.sh worker-3"
echo "  oc apply -f ocp/ostest/worker-3_bmh.yaml"
echo ""
echo "  # Scale machineset to match (3 new workers)"
echo "  oc scale machineset \$(oc get machineset -n openshift-machine-api -o name | head -1 | cut -d/ -f2) --replicas=5 -n openshift-machine-api"
echo ""

# ============================================================================
# Example 4: Complete workflow with auto-CSR approval
# ============================================================================
echo "Example 4: Complete workflow with automatic CSR approval"
echo ""
echo "Commands:"
echo "  # Start CSR auto-approval in background"
echo "  ./auto_approve_csrs.sh 30 &"
echo "  CSR_PID=\$!"
echo ""
echo "  # Add and apply worker"
echo "  ./add_worker_node.sh test-worker"
echo "  oc apply -f ocp/ostest/test-worker_bmh.yaml"
echo ""
echo "  # Wait for BareMetalHost to be available"
echo "  echo 'Waiting for BareMetalHost to be available...'"
echo "  oc wait --for=jsonpath='{.status.provisioning.state}'=available \\"
echo "    baremetalhost/${CLUSTER_NAME}-test-worker \\"
echo "    -n openshift-machine-api --timeout=10m"
echo ""
echo "  # Scale machineset"
echo "  CURRENT_REPLICAS=\$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.replicas}')"
echo "  NEW_REPLICAS=\$((CURRENT_REPLICAS + 1))"
echo "  oc scale machineset \$(oc get machineset -n openshift-machine-api -o name | head -1 | cut -d/ -f2) \\"
echo "    --replicas=\$NEW_REPLICAS -n openshift-machine-api"
echo ""
echo "  # Wait for node to be ready"
echo "  echo 'Waiting for node to be ready...'"
echo "  oc wait --for=condition=Ready node/${CLUSTER_NAME}-test-worker --timeout=20m"
echo ""
echo "  # Stop CSR approval (it will auto-stop after 30 minutes anyway)"
echo "  kill \$CSR_PID 2>/dev/null || true"
echo ""

# ============================================================================
# Example 5: Using Make targets
# ============================================================================
echo "Example 5: Using Make targets (simplest method)"
echo ""
echo "Commands:"
echo "  # Add worker"
echo "  make add_worker WORKER_NAME=my-worker"
echo ""
echo "  # Apply manifest (still manual step)"
echo "  oc apply -f ocp/ostest/my-worker_bmh.yaml"
echo ""
echo "  # Scale machineset (still manual step)"
echo "  oc scale machineset <name> --replicas=<N+1> -n openshift-machine-api"
echo ""
echo "  # Later: Remove worker"
echo "  make remove_worker WORKER_NAME=my-worker"
echo ""

# ============================================================================
# Example 6: Remove a worker node
# ============================================================================
echo "Example 6: Remove a worker node"
echo ""
echo "Commands:"
echo "  # Scale down machineset first"
echo "  CURRENT_REPLICAS=\$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.replicas}')"
echo "  NEW_REPLICAS=\$((CURRENT_REPLICAS - 1))"
echo "  oc scale machineset \$(oc get machineset -n openshift-machine-api -o name | head -1 | cut -d/ -f2) \\"
echo "    --replicas=\$NEW_REPLICAS -n openshift-machine-api"
echo ""
echo "  # Wait for machine to be deleted"
echo "  echo 'Waiting for machine deletion...'"
echo "  sleep 60"
echo ""
echo "  # Remove the worker and clean up"
echo "  ./remove_worker_node.sh my-worker"
echo ""

# ============================================================================
# Example 7: Check worker status
# ============================================================================
echo "Example 7: Monitoring worker status"
echo ""
echo "Commands:"
echo "  # Check BareMetalHosts"
echo "  oc get baremetalhost -n openshift-machine-api"
echo ""
echo "  # Check Machines"
echo "  oc get machines -n openshift-machine-api"
echo ""
echo "  # Check Nodes"
echo "  oc get nodes"
echo ""
echo "  # Watch node joining process"
echo "  oc get nodes -w"
echo ""
echo "  # Check pending CSRs"
echo "  oc get csr | grep Pending"
echo ""
echo "  # Check specific BareMetalHost details"
echo "  oc describe baremetalhost ${CLUSTER_NAME}-worker-name -n openshift-machine-api"
echo ""

# ============================================================================
# Example 8: Troubleshooting
# ============================================================================
echo "Example 8: Troubleshooting commands"
echo ""
echo "Commands:"
echo "  # Check VM status"
echo "  sudo virsh list --all | grep ${CLUSTER_NAME}"
echo ""
echo "  # Start a VM if it's stopped"
echo "  sudo virsh start ${CLUSTER_NAME}_worker-name"
echo ""
echo "  # Check VM console"
echo "  sudo virsh console ${CLUSTER_NAME}_worker-name"
echo ""
echo "  # Check DHCP leases"
echo "  sudo virsh net-dhcp-leases baremetal"
echo ""
echo "  # Check baremetal operator logs"
echo "  oc logs -n openshift-machine-api deployment/metal3 -c baremetal-operator --tail=50"
echo ""
echo "  # Check machine controller logs"
echo "  oc logs -n openshift-machine-api deployment/machine-api-controllers -c machine-controller --tail=50"
echo ""

echo "=========================================="
echo "For more information, see:"
echo "  - WORKER_QUICK_START.md"
echo "  - docs/add-worker-post-install.md"
echo "=========================================="

