#!/bin/bash -xe

source common.sh

# Save the image configuration in case the goal is to start a local
# copy of the CBO. If there is no pod, we don't want the command to
# fail.
pod=$(oc get pod -n openshift-machine-api -o name | grep cluster-baremetal-operator || true)
if [ -n "$pod" ]; then
    oc exec $pod -n openshift-machine-api -c cluster-baremetal-operator \
       -- cat /etc/cluster-baremetal-operator/images/images.json > ${OCP_DIR}/cbo-images.json
    echo "CBO image settings saved to ${OCP_DIR}/cbo-images.json"
else
    echo "No CBO pod found, cannot save image settings"
fi

# Tell the cluster-version-operator to stop managing the
# cluster-baremetal-operator and baremetalhost CRD
oc patch clusterversion version --namespace openshift-cluster-version --type merge -p '{"spec":{"overrides":[{"kind":"Deployment","group":"apps","name":"cluster-baremetal-operator","namespace":"openshift-machine-api","unmanaged":true},{"kind":"CustomResourceDefinition","group":"apiextensions.k8s.io","name":"baremetalhosts.metal3.io","namespace":"","unmanaged":true}]}}'

# Stop any existing machine-api-operator
oc scale deployment -n openshift-machine-api --replicas=0 cluster-baremetal-operator
