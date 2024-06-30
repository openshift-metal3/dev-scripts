#!/usr/bin/env bash
set -x
set -e

source logging.sh
source common.sh
source network.sh
source ocp_install_env.sh
source release_info.sh
source utils.sh
source rhcos.sh
source validation.sh

early_deploy_validation

if [[ ! -z "$INSTALLER_PROXY" ]]; then
  export HTTP_PROXY=${HTTP_PROXY}
  export HTTPS_PROXY=${HTTPS_PROXY}
  export NO_PROXY=${NO_PROXY}
fi

# Call openshift-installer to deploy the bootstrap node and masters
create_cluster ${OCP_DIR}

# Kill the dnsmasq container on the host since it is performing DHCP and doesn't
# allow our pod in openshift to take over.  We don't want to take down all of ironic
# as it makes cleanup "make clean" not work properly.
for name in dnsmasq ironic-inspector ; do
    sudo podman ps | grep -w "$name$" && sudo podman stop $name
done


# Default to emptyDir for image-reg storage
if [ "${PERSISTENT_IMAGEREG}" != true ] ; then
    oc patch configs.imageregistry.operator.openshift.io \
        cluster --type merge --patch '{"spec":{"storage":{"emptyDir":{}},"managementState":"Managed"}}'
else
    oc apply -f - <<EOF
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv1
spec:
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteMany
  nfs:
    path: /opt/dev-scripts/nfsshare/1
    server: $LOCAL_REGISTRY_DNS_NAME
    readOnly: false
EOF
    oc patch configs.imageregistry.operator.openshift.io \
        cluster --type merge --patch '{"spec":{"storage":{"pvc":{"claim":""}},"managementState":"Managed","replicas": 2}}'
fi

if [[ ! -z "${ENABLE_LOCAL_REGISTRY}" ]]; then
    # Configure tools image registry and cluster samples operator
    # when local image stream is enabled. These are basically to run CI tests
    # depend on tools image.
    add_local_certificate_as_trusted
fi

# Marketplace operators could not pull their images via internet
# and stays degraded in disconnected.
# This is the suggested way in
# https://docs.openshift.com/container-platform/4.9/operators/admin/olm-managing-custom-catalogs.html#olm-restricted-networks-operatorhub_olm-managing-custom-catalogs
if [[ -n "${MIRROR_IMAGES}" && "${MIRROR_IMAGES,,}" != "false" ]]; then
  oc patch OperatorHub cluster --type json \
      -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'
fi

if [[ -n "${APPLY_EXTRA_WORKERS}" ]]; then
    if [[ ${NUM_EXTRA_WORKERS} -ne 0 && -s "${OCP_DIR}/extra_host_manifests.yaml" ]]; then
        oc apply -f "${OCP_DIR}/extra_host_manifests.yaml"

        for h in $(jq -r '.[].name' ${EXTRA_BAREMETALHOSTS_FILE}); do
            while ! oc get baremetalhost -n openshift-machine-api $h 2>/dev/null; do
                echo "Waiting for $h"
                sleep 5
            done
            echo "$h is successfully applied"
        done
    else
        echo "NUM_EXTRA_WORKERS should be set and extra_host_manifests.yaml should exist"
    fi
fi

# Create a secret containing extraworkers info for the e2e tests
if [[ ${NUM_EXTRA_WORKERS} -ne 0 && -d "${OCP_DIR}/extras" ]]; then
    oc create secret generic extraworkers-secret --from-file="${OCP_DIR}/extras/" -n openshift-machine-api
fi

if [[ ! -z "${ENABLE_METALLB}" ]]; then

	if [[ -z ${METALLB_IMAGE_BASE} ]]; then
                # This can use any image in the release, as we are dropping
                # the hash
		export METALLB_IMAGE_BASE=$(\
			image_for cli | sed -e 's/@.*$//g')
		export METALLB_IMAGE_TAG="metallb"
		export FRR_IMAGE_TAG="metallb-frr"
	fi

	pushd metallb
	./configure_metallb.sh
	popd
fi

if [[ ! -z "${ENABLE_VIRTUAL_MEDIA_VIA_EXTERNAL_NETWORK}" ]]; then
    oc patch provisioning provisioning-configuration --type merge -p "{\"spec\":{\"virtualMediaViaExternalNetwork\":true}}"
fi

echo "Cluster up, you can interact with it via oc --kubeconfig ${KUBECONFIG} <command>"
echo "To avoid using the --kubeconfig flag on each command, set KUBECONFIG variable with: export KUBECONFIG=${KUBECONFIG}"

