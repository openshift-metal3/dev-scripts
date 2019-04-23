#!/bin/bash

# https://github.com/openshift-metal3/dev-scripts/issues/260

export KUBECONFIG=$(dirname $0)/ocp/auth/kubeconfig
for cert in $(oc get csr -o name); do
    oc adm certificate approve "${cert}"
done
