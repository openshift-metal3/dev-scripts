#!/bin/bash -xe

# Tell the cluster-version-operator to resume managing the machine-api-operator
oc patch clusterversion version --namespace openshift-cluster-version --type merge -p '{"spec":{"overrides":[{"kind":"Deployment","group":"apps","name":"machine-api-operator","namespace":"openshift-machine-api","unmanaged":false}]}}'
