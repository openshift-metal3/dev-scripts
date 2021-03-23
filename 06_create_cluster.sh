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
    
    oc patch configs.samples cluster \
      --type merge --patch "{\"spec\":{\"samplesRegistry\":\"${LOCAL_REGISTRY_DNS_NAME}\"}}"
fi

echo "Cluster up, you can interact with it via oc --config ${KUBECONFIG} <command>"
