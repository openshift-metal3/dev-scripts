#!/usr/bin/env sh

set -ex

# This depends on:
# export FEATURE_SET=TechPreviewNoUpgrade
# export BMO_WATCH_ALL_NAMESPACES="true"
# export NUM_EXTRA_WORKERS=1
# export EXTRA_WORKERS_NAMESPACE="openshift-cluster-api"

CLUSTER_NAME=${CLUSTER_NAME:-ostest}
SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

export KUBECONFIG="${SCRIPTDIR}/ocp/${CLUSTER_NAME}/auth/kubeconfig"

while ! oc get namespace openshift-cluster-api 2>/dev/null; do
    echo "Waiting for openshift-cluster-api namespace to be created."
    sleep 5
done
oc apply -f ocp/ostest/extra_host_manifests.yaml
oc get secret worker-user-data-managed -n openshift-machine-api -o yaml | sed 's/namespace: .*/namespace: openshift-cluster-api/' | oc apply -f -
