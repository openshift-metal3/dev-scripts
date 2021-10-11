#!/usr/bin/env bash
set -x
set -e

source logging.sh
source common.sh
source network.sh
source utils.sh
source ocp_install_env.sh
source rhcos.sh
source validation.sh

early_deploy_validation

# Call openshift-installer to deploy the bootstrap node and masters
create_cluster ${OCP_DIR}

# Kill the dnsmasq container on the host since it is performing DHCP and doesn't
# allow our pod in openshift to take over.  We don't want to take down all of ironic
# as it makes cleanup "make clean" not work properly.
for name in dnsmasq ironic-inspector ; do
    sudo podman ps | grep -w "$name$" && sudo podman stop $name
done

# Configure storage for the image registry
oc patch configs.imageregistry.operator.openshift.io \
    cluster --type merge --patch '{"spec":{"storage":{"emptyDir":{}},"managementState":"Managed"}}'

if [[ ! -z "${ENABLE_LOCAL_REGISTRY}" ]]; then        
    # Configure tools image registry and cluster samples operator 
    # when local image stream is enabled. These are basically to run CI tests
    # depend on tools image.
    add_local_certificate_as_trusted
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

if [[ ! -z "${ENABLE_METALLB_MODE}" ]]; then

	if [[ -z ${METALLB_IMAGE_BASE} ]]; then
		export METALLB_IMAGE_BASE=$(\
			jq -r .references.spec.tags[0].from.name ${OCP_DIR}/release_info.json | sed -e 's/@.*$//g')
		export METALLB_IMAGE_TAG="metallb"
	fi

	pushd metallb
	./configure_metallb.sh
	popd

	if [[ ${ENABLE_METALLB_MODE} == "bgp" ]]; then
		pushd metallb
		./start_frr.sh
		popd
	elif [[ ${ENABLE_METALLB_MODE} != "l2" ]]; then
		echo "metallb is not configured because wrong ENABLE_METALLB_MODE set, ${ENABLE_METALLB_MODE}"
	fi
fi

echo "Cluster up, you can interact with it via oc --config ${KUBECONFIG} <command>"
