#!/bin/bash -xe

CUSTOM_MAO_IMAGE=${CUSTOM_MAO_IMAGE:-$1}
if [ -z "$CUSTOM_MAO_IMAGE" ]; then
    # Custom MAO image not already provided
    echo "Usage: ./run-custom-mao.sh <machine-api-operator image> <repo name> <branch name>"
    echo "Machine-api-operator image to be tested is mandatory."
    echo "repo_name and branch_name are optional parameters."
    echo "If these are not provided, they will default to \"openshift\" and \"master\" respectively."
    echo "Example: ./run-custom-mao.sh quay.io/sdasu/machine-api-operator:sdasu-fix sadasu sdasu-fix"
    echo "Input parameters can also be provided via CUSTOM_MAO_IMAGE, REPO_NAME and MAO_BRANCH resp."
    echo "Also, this script assumes that it is run after a successful dev-scripts install."
    exit 1
fi

REPO_NAME=${REPO_NAME:-${2:-openshift}}
MAO_BRANCH=${MAO_BRANCH:-${3:-master}}
CLUSTER_NAME=${CLUSTER_NAME:-ostest}

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export KUBECONFIG="${SCRIPTDIR}/ocp/${CLUSTER_NAME}/auth/kubeconfig"

REPLACEMENT_TEXT="image: ${CUSTOM_MAO_IMAGE}"
MAO_REPO="raw.githubusercontent.com/${REPO_NAME}/machine-api-operator"
MAO_RBAC_MANIFEST="install/0000_30_machine-api-operator_09_rbac.yaml"

wait_for_metal3_to_terminate() {
    echo "Waiting for metal3 pod to terminate..."
    METAL3_POD=$(oc --request-timeout=5s --config ${KUBECONFIG} get pods --namespace openshift-machine-api | grep metal3 | awk '{print $1}')
    while [ "$(oc --config ${KUBECONFIG} get pods -n openshift-machine-api | grep ${METAL3_POD})" != "" ]; do sleep 5; done
}

wait_for_metal3_to_start() {
    echo "Waiting for metal3 pod to start..."
    while [ "$(oc --config ${KUBECONFIG} get pods -n openshift-machine-api | grep metal3 | wc -l)" != 1 ]; do sleep 5; done
}

update_mao_rbac() {
    wget https://${MAO_REPO}/${MAO_BRANCH}/${MAO_RBAC_MANIFEST} -O ${SCRIPTDIR}/ocp/machine-api-operator-roles.yaml

    # Give the machine-api-operator rbac access to create and read secrets
    oc --config ${KUBECONFIG} apply -f ${SCRIPTDIR}/ocp/machine-api-operator-roles.yaml
}

replace_mao_image() {
    #Replace the MAO image with the one provided as input param
    oc --config ${KUBECONFIG} get deployments -n openshift-machine-api machine-api-operator -o yaml > ${SCRIPTDIR}/ocp/mao.yaml
    sed -i -e "s!image: .*!${REPLACEMENT_TEXT}!g" ${SCRIPTDIR}/ocp/mao.yaml
    oc --config ${KUBECONFIG} apply -f ${SCRIPTDIR}/ocp/mao.yaml
}

check_if_new_mariadb_password_exists() {
    if [ "$(oc --config ${KUBECONFIG} get secrets --namespace openshift-machine-api | grep metal3-mariadb-password | wc -l)" != 1 ]; then
      exit 1
    else
      echo "New metal3-mariadb-password successfully created."
    fi
}

# Stop CVO, MAO and Metal3 deployments
oc --config ${KUBECONFIG} scale deployment --replicas=0 cluster-version-operator --namespace openshift-cluster-version
oc --config ${KUBECONFIG} scale deployment --replicas=0 machine-api-operator --namespace openshift-machine-api
oc --config ${KUBECONFIG} scale deployment --replicas=0 metal3 --namespace openshift-machine-api

wait_for_metal3_to_terminate

update_mao_rbac

replace_mao_image

oc --config ${KUBECONFIG} scale deployment --replicas=1 machine-api-operator --namespace openshift-machine-api

wait_for_metal3_to_start

check_if_new_mariadb_password_exists
