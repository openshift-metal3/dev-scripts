#!/usr/bin/env bash
set -x
set -e

source logging.sh
source common.sh
source network.sh
source utils.sh
source ocp_install_env.sh
source rhcos.sh

# Call openshift-installer to deploy the bootstrap node and masters
create_cluster ${OCP_DIR}

# Kill the dnsmasq container on the host since it is performing DHCP and doesn't
# allow our pod in openshift to take over.  We don't want to take down all of ironic
# as it makes cleanup "make clean" not work properly.
for name in dnsmasq ironic-inspector ; do
    sudo podman ps | grep -w "$name$" && sudo podman stop $name
done

echo "Cluster up, you can interact with it via oc --config ${KUBECONFIG} <command>"
