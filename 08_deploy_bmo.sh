#!/usr/bin/bash

set -ex

source logging.sh
#source common.sh
eval "$(go env)"

# Get the latest bits for baremetal-operator
export BMOPATH="$GOPATH/src/github.com/metal3-io/baremetal-operator"

# Make a local copy of the baremetal-operator code to make changes
cp -r $BMOPATH/deploy ocp/.
sed -i 's/namespace: .*/namespace: openshift-machine-api/g' ocp/deploy/role_binding.yaml
# FIXME(dhellmann): Use the pre-rename operator until this repo
# works with the renamed version.
# Other pre-reqs before this can be removed:
# - machine-api-operator includes updated RBAC for the metal3.io API
#   https://github.com/openshift/machine-api-operator/pull/296
# - openshift/cluster-api-provider-baremetal must get updated to include
#   https://github.com/metal3-io/cluster-api-provider-baremetal/pull/63
#   which switches it to the metal3.io API.
# - We switch to a pinned release of OpenShift that includes builds of
#   CAPBM and MAO with the above changes.
sed -i 's|image: quay.io/metalkube/baremetal-operator$|image: quay.io/metalkube/baremetal-operator:metalkube|' ocp/deploy/operator.yaml

# Start deploying on the new cluster
oc --config ocp/auth/kubeconfig apply -f ocp/deploy/service_account.yaml --namespace=openshift-machine-api
oc --config ocp/auth/kubeconfig apply -f ocp/deploy/role.yaml --namespace=openshift-machine-api
oc --config ocp/auth/kubeconfig apply -f ocp/deploy/role_binding.yaml
oc --config ocp/auth/kubeconfig apply -f ocp/deploy/crds/metal3_v1alpha1_baremetalhost_crd.yaml
oc --config ocp/auth/kubeconfig apply -f ocp/deploy/operator.yaml --namespace=openshift-machine-api

# Workaround for https://github.com/metal3-io/cluster-api-provider-baremetal/issues/57
oc --config ocp/auth/kubeconfig scale deployment -n openshift-machine-api machine-api-controllers --replicas=0
while [ ! $(oc --config ocp/auth/kubeconfig get deployment -n openshift-machine-api machine-api-controllers -o json | jq .spec.replicas) ]
do
  echo "Scaling down machine-api-controllers ..."
done
echo "Scaling up machine-api-controllers ..."
oc --config ocp/auth/kubeconfig scale deployment -n openshift-machine-api machine-api-controllers --replicas=1
