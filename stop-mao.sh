#!/bin/bash -xe

# Tell the cluster-version-operator to stop managing the machine-api-operator
oc patch clusterversion version --namespace openshift-cluster-version --type merge -p '{"spec":{"overrides":[{"kind":"Deployment","group":"apps/v1","name":"machine-api-operator","namespace":"openshift-machine-api","unmanaged":true}]}}'

# Stop any existing machine-api-operator
oc scale deployment -n openshift-machine-api --replicas=0 machine-api-operator
