#!/usr/bin/bash

set -ex

source logging.sh
source common.sh
eval "$(go env)"

DEV_SCRIPTS_DIR=$(realpath $(dirname $0))
KUBECONFIG="${DEV_SCRIPTS_DIR}/ocp/auth/kubeconfig"

custom_capbm() {
    test -n "${CAPBM_IMAGE_SOURCE:-}"
}
custom_mao() {
    test "${USE_CUSTOM_MAO:-false}" = "true"
}

sudo podman stop machine-api-operator || echo 'No local machine-api-operator running'

if custom_capbm || custom_mao; then
    oc --config=${KUBECONFIG} patch clusterversion version --namespace openshift-cluster-version --type merge -p '{"spec":{"overrides":[{"kind":"Deployment","group":"","name":"machine-api-operator","namespace":"openshift-machine-api","unmanaged":true}]}}'

    MAO_REPO="github.com/openshift/machine-api-operator"
    MAO_BRANCH="release-4.2"
    IMAGES_FILE="pkg/operator/fixtures/images.json"

    MAO_IMAGES="${DEV_SCRIPTS_DIR}/ocp/deploy/mao-images.json"
    mkdir -p $(dirname ${MAO_IMAGES})

    save_images_file() {
        sed -e 's/docker/quay/' -e 's/v4.0.0/4.2.0/' >${MAO_IMAGES}
    }

    if custom_mao; then
        oc --config=${KUBECONFIG} scale deployment -n openshift-machine-api --replicas=0 machine-api-operator

        MAO_PATH="${GOPATH}/src/${MAO_REPO}"

        if [ ! -d "${MAO_PATH}" ]; then
            go get -d "${MAO_REPO}/cmd/machine-api-operator"

            pushd ${MAO_PATH}
            git checkout ${MAO_BRANCH}
        else
            pushd ${MAO_PATH}
        fi

        save_images_file <${IMAGES_FILE}
    else
        wget -O - https://${MAO_REPO/github.com/raw.githubusercontent.com}/${MAO_BRANCH}/${IMAGES_FILE} | save_images_file
    fi

    if custom_capbm; then
        sed -i -e "/clusterAPIControllerBareMetal/ s|: \"[^\"]*\"|: \"${CAPBM_IMAGE_SOURCE}\"|" ${MAO_IMAGES}
    fi

    if custom_mao; then
        sudo podman run --rm -v ${MAO_PATH}:/go/src/${MAO_REPO}:Z -w /go/src/${MAO_REPO} golang:1.10 ./hack/go-build.sh machine-api-operator
        popd

        # Run our machine-api-operator locally
        sudo podman create --rm -v ${MAO_PATH}:/go/src/${MAO_REPO}:Z -v $(dirname ${MAO_IMAGES})/..:/ocp:Z -w /go/src/${MAO_REPO} --name machine-api-operator --net=host alpine ./bin/machine-api-operator start --images-json=/ocp/deploy/$(basename ${MAO_IMAGES}) --kubeconfig=/ocp/auth/kubeconfig --v=4
        sudo podman start machine-api-operator
    else
        # Create a new configMap with the images we want
        CONFIG_NAME="machine-api-operator-images-$(date -u +%Y%m%d%H%M%S)"
        cat <<EOF | oc --config=${KUBECONFIG} apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${CONFIG_NAME}
  namespace: openshift-machine-api
data:
  images.json: >
$(cat ${MAO_IMAGES} | sed -e 's/^/    /')
EOF

        # Use our new configMap. Note that this takes 2 minutes before the
        # machine-api-controllers pod is updated with the new images
        oc --config=${KUBECONFIG} patch deployment machine-api-operator --namespace openshift-machine-api --type json -p '[{"op": "replace", "path": "/spec/template/spec/volumes/0/configMap/name", "value": "'${CONFIG_NAME}'"}]'
        # Clean up any old config maps
        oc --config=${KUBECONFIG} delete $(oc --config=${KUBECONFIG} get configmap -o name | egrep 'machine-api-operator-images-[0-9]{14}' | grep -v "${CONFIG_NAME}")
        # Scale to 1 replica in case we previously used a local MAO
        oc --config=${KUBECONFIG} scale deployment -n openshift-machine-api --replicas=1 machine-api-operator
    fi
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
