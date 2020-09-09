#!/bin/bash -xe

source common.sh

# Save the image configuration in case the goal is to start a local
# copy of the MAO. If there is no pod, we don't want the command to
# fail.
pod=$(oc get pod -n openshift-machine-api -o name | grep machine-api-operator || true)
if [ -n "$pod" ]; then
    oc exec $pod -n openshift-machine-api -c machine-api-operator \
       -- cat /etc/machine-api-operator-config/images/images.json > ${OCP_DIR}/mao-images.json
    echo "MAO image settings saved to ${OCP_DIR}/mao-images.json"
else
    echo "No MAO pod found, cannot save image settings"
fi

# Tell the cluster-version-operator to stop managing the machine-api-operator
oc patch clusterversion version --namespace openshift-cluster-version --type merge -p '{"spec":{"overrides":[{"kind":"Deployment","group":"apps/v1","name":"machine-api-operator","namespace":"openshift-machine-api","unmanaged":true}]}}'

# Stop any existing machine-api-operator
oc scale deployment -n openshift-machine-api --replicas=0 machine-api-operator
