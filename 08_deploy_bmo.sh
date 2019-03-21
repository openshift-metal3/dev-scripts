#!/usr/bin/bash

eval "$(go env)"

# Get the latest bits for baremetal-operator
export BMOPATH="$GOPATH/src/github.com/metalkube/baremetal-operator"

source common.sh

oc new-project bmo-project

# Start deploying on the new cluster

oc apply -f $BMOPATH/deploy/service_account.yaml
oc apply -f $BMOPATH/deploy/role.yaml
oc apply -f $BMOPATH/deploy/role_binding.yaml
oc apply -f $BMOPATH/deploy/crds/metalkube_v1alpha1_baremetalhost_crd.yaml
oc apply -f $BMOPATH/deploy/operator.yaml
