#!/usr/bin/bash

set -ex

source logging.sh
source common.sh
eval "$(go env)"

DEV_SCRIPTS_DIR=$(realpath $(dirname $0))
KUBECONFIG="${DEV_SCRIPTS_DIR}/ocp/auth/kubeconfig"

sudo podman stop machine-api-operator || echo 'No local machine-api-operator running'

if [ -n "${CAPBM_IMAGE_SOURCE:-}" ]; then
    oc --config=${KUBECONFIG} patch clusterversion version --namespace openshift-cluster-version --type merge -p '{"spec":{"overrides":[{"kind":"Deployment","group":"","name":"machine-api-operator","namespace":"openshift-machine-api","unmanaged":true}]}}'

    oc --config=${KUBECONFIG} scale deployment -n openshift-machine-api --replicas=0 machine-api-operator

    # This is in the instructions but doesn't seem to be required (deployment does not exist)
    #oc --config=${KUBECONFIG} delete deployment -n openshift-machine-api clusterapi-manager-controllers

    MAO_PATH="${GOPATH}/src/github.com/openshift/machine-api-operator"
    IMAGES_FILE="pkg/operator/fixtures/images.json"

    if [ ! -d "${MAO_PATH}" ]; then
        go get -d github.com/openshift/machine-api-operator/cmd/machine-api-operator

        pushd ${MAO_PATH}
        git checkout release-4.2

        sed -i -e 's/docker/quay/' -e 's/v4.0.0/4.2.0/' "${IMAGES_FILE}"
        if ! git diff --quiet -- "${IMAGES_FILE}"; then
            git add "${IMAGES_FILE}"
            git commit -m 'Use 4.2 images'
        fi
    else
        pushd ${MAO_PATH}
    fi

    sed -e "/cluster-api-provider-baremetal/ s/http:.*/${CAPBM_IMAGE_SOURCE}/" "${MAO_PATH}/${IMAGES_FILE}" >ocp/deploy/mao-images.json

    sudo podman run --rm -v ${MAO_PATH}:/go/src/github.com/openshift/machine-api-operator:Z -w /go/src/github.com/openshift/machine-api-operator golang:1.10 ./hack/go-build.sh machine-api-operator
    popd

    # Run our machine-api-operator locally
    sudo podman create --rm -v ${MAO_PATH}:/go/src/${MAO_REPO}:Z -v $(dirname ${MAO_IMAGES})/..:/ocp:Z -w /go/src/${MAO_REPO} --name machine-api-operator --net=host alpine ./bin/machine-api-operator start --images-json=/ocp/deploy/$(basename ${MAO_IMAGES}) --kubeconfig=/ocp/auth/kubeconfig --v=4
    sudo podman start machine-api-operator
else
    # Remove any overrides so that the CVO will begin managing things again
    oc --config=${KUBECONFIG} patch clusterversion version --namespace openshift-cluster-version --type merge -p '{"spec":{"overrides":[]}}'
fi

# Set default value for provisioning interface
CLUSTER_PRO_IF=${CLUSTER_PRO_IF:-ens3}

# Get Baremetal ip
BAREMETAL_IP=$(ip -o -f inet addr show baremetal | awk '{print $4}' | tail -1 | cut -d/ -f1)

# Get the latest bits for baremetal-operator
export BMOPATH="$GOPATH/src/github.com/metal3-io/baremetal-operator"

# Make a local copy of the baremetal-operator code to make changes
cp -r $BMOPATH/deploy ocp/.
sed -i 's/namespace: .*/namespace: openshift-machine-api/g' ocp/deploy/role_binding.yaml

cp $SCRIPTDIR/operator_ironic.yaml ocp/deploy
cp $SCRIPTDIR/ironic_bmo_configmap.yaml ocp/deploy
sed -i "s#__RHCOS_IMAGE_URL__#${RHCOS_IMAGE_URL}#" ocp/deploy/ironic_bmo_configmap.yaml
sed -i "s#provisioning_interface: \"ens3\"#provisioning_interface: \"${CLUSTER_PRO_IF}\"#" ocp/deploy/ironic_bmo_configmap.yaml
sed -i "s#cache_url: \"http://192.168.111.1/images\"#cache_url: \"http://${BAREMETAL_IP}/images\"#" ocp/deploy/ironic_bmo_configmap.yaml

# Kill the dnsmasq container on the host since it is performing DHCP and doesn't
# allow our pod in openshift to take over.  We don't want to take down all of ironic
# as it makes cleanup "make clean" not work properly.
for name in dnsmasq ironic-inspector ; do
    sudo podman ps | grep -w "$name$" && sudo podman stop $name
done

# Start deploying on the new cluster
oc --config ocp/auth/kubeconfig apply -f ocp/deploy/service_account.yaml --namespace=openshift-machine-api
oc --config ocp/auth/kubeconfig apply -f ocp/deploy/role.yaml --namespace=openshift-machine-api
oc --config ocp/auth/kubeconfig apply -f ocp/deploy/role_binding.yaml
oc --config ocp/auth/kubeconfig apply -f ocp/deploy/crds/metal3_v1alpha1_baremetalhost_crd.yaml

oc --config ocp/auth/kubeconfig apply -f ocp/deploy/ironic_bmo_configmap.yaml --namespace=openshift-machine-api
# I'm leaving this as is for debugging but we could easily generate a random password here.
oc --config ocp/auth/kubeconfig delete secret mariadb-password --namespace=openshift-machine-api || true
oc --config ocp/auth/kubeconfig create secret generic mariadb-password --from-literal password=password --namespace=openshift-machine-api

oc --config ocp/auth/kubeconfig adm --as system:admin policy add-scc-to-user privileged system:serviceaccount:openshift-machine-api:baremetal-operator
oc --config ocp/auth/kubeconfig apply -f ocp/deploy/operator_ironic.yaml -n openshift-machine-api
