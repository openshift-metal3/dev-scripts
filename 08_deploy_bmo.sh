#!/usr/bin/bash

eval "$(go env)"

# Get the latest bits for baremetal-operator
export BMOPATH="$GOPATH/src/github.com/metalkube/baremetal-operator"

oc --as system:admin --config ocp/auth/kubeconfig new-project bmo-project

# Start deploying on the new cluster

oc --as system:admin --config ocp/auth/kubeconfig apply -f $BMOPATH/deploy/service_account.yaml
oc --as system:admin --config ocp/auth/kubeconfig apply -f $BMOPATH/deploy/role.yaml
oc --as system:admin --config ocp/auth/kubeconfig apply -f $BMOPATH/deploy/role_binding.yaml
oc --as system:admin --config ocp/auth/kubeconfig apply -f $BMOPATH/deploy/crds/metalkube_v1alpha1_baremetalhost_crd.yaml
oc --as system:admin --config ocp/auth/kubeconfig apply -f $BMOPATH/deploy/operator.yaml
