#!/usr/bin/bash

set -ex

source common.sh
source ocp_install_env.sh
source logging.sh

# The deployment is complete, but we must manually add the IPs for the masters,
# as we don't have a way to do that automatically yet. This is required for
# CSRs to get auto approved for masters.
# https://github.com/openshift-metal3/dev-scripts/issues/260
# https://github.com/metal3-io/baremetal-operator/issues/242
./add-machine-ips.sh

# Bounce the machine approver to get it to notice the changes.
oc scale deployment -n openshift-cluster-machine-approver --replicas=0 machine-approver
while [ ! $(oc get deployment -n openshift-cluster-machine-approver machine-approver -o json | jq .spec.replicas) ]
do
  echo "Scaling down machine-approver..."
done
echo "Scaling up machine-approver..."
oc scale deployment -n openshift-cluster-machine-approver --replicas=1 machine-approver

# Wait a tiny bit, then list the csrs
sleep 5
oc get csr
