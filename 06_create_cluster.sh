#!/usr/bin/env bash
set -x
set -e

source logging.sh
source utils.sh
source common.sh
source ocp_install_env.sh

# Do some PULL_SECRET sanity checking
if [[ "${OPENSHIFT_RELEASE_IMAGE}" == *"registry.svc.ci.openshift.org"* ]]; then
    if [[ "${PULL_SECRET}" != *"registry.svc.ci.openshift.org"* ]]; then
        echo "Please get a valid pull secret for registry.svc.ci.openshift.org."
        exit 1
    fi
fi

if [[ "${PULL_SECRET}" != *"cloud.openshift.com"* ]]; then
    echo "Please get a valid pull secret for cloud.openshift.com."
    exit 1
fi

if [ ! -d ocp ]; then
    mkdir -p ocp

    if [ -z "$INSTALL_FROM_GIT" ]; then
      # Extract openshift-install from the release image
      extract_installer "${OPENSHIFT_RELEASE_IMAGE}" ocp/
    else
      # Clone and build the installer from source
      clone_installer
      build_installer
    fi

    # Create a master_nodes.json file
    jq '.nodes[0:3] | {nodes: .}' "${NODES_FILE}" | tee "${MASTER_NODES_FILE}"

    # Create install config for openshift-installer
    generate_ocp_install_config ocp
fi

# NOTE: This is equivalent to the external API DNS record pointing the API to the API VIP
if [ "$MANAGE_BR_BRIDGE" == "y" ] ; then
    API_VIP=$(dig +noall +answer "api.${CLUSTER_DOMAIN}" @$(network_ip baremetal) | awk '{print $NF}')
    INGRESS_VIP=$(python -c "from ansible.plugins.filter import ipaddr; print(ipaddr.nthhost('"$EXTERNAL_SUBNET"', 4))")
    echo "address=/api.${CLUSTER_DOMAIN}/${API_VIP}" | sudo tee /etc/NetworkManager/dnsmasq.d/openshift.conf
    echo "address=/.apps.${CLUSTER_DOMAIN}/${INGRESS_VIP}" | sudo tee -a /etc/NetworkManager/dnsmasq.d/openshift.conf
    sudo systemctl reload NetworkManager
else
    API_VIP=$(dig +noall +answer "api.${CLUSTER_DOMAIN}"  | awk '{print $NF}')
    INGRESS_VIP=$(dig +noall +answer "test.apps.${CLUSTER_DOMAIN}" | awk '{print $NF}')
fi

# Make sure Ironic is up
export OS_TOKEN=fake-token
export OS_URL=http://localhost:6385/

wait_for_json ironic \
    "${OS_URL}/v1/nodes" \
    20 \
    -H "Accept: application/json" -H "Content-Type: application/json" -H "User-Agent: wait-for-json" -H "X-Auth-Token: $OS_TOKEN"

if [ $(sudo podman ps | grep -w -e "ironic$" -e "ironic-inspector$" -e "dnsmasq" -e "httpd" | wc -l) != 4 ]; then
    echo "Can't find required containers"
    exit 1
fi

# Call kni-installer to deploy the bootstrap node and masters
create_cluster ocp

# Run the fix_certs.sh script periodically as a workaround for
# https://github.com/openshift-metalkube/dev-scripts/issues/260
sudo systemd-run --on-active=30s --on-unit-active=30m --unit=fix_certs.service $(dirname $0)/fix_certs.sh

# Update kube-system ep/host-etcd used by cluster-kube-apiserver-operator to
# generate storageConfig.urls
patch_ep_host_etcd "$CLUSTER_DOMAIN"

echo "Master nodes up, you can ssh to the following IPs with core@<IP>"
sudo virsh net-dhcp-leases baremetal

# disable NoSchedule taints for masters until we have workers deployed
oc adm taint nodes -l node-role.kubernetes.io/master node-role.kubernetes.io/master:NoSchedule-

./add-machine-ips.sh

# Bounce the machine approver to get it to notice the changes.
oc scale deployment -n openshift-cluster-machine-approver --replicas=0 machine-approver
while [ ! $(oc get deployment -n openshift-cluster-machine-approver machine-approver -o json | jq .spec.replicas) ]
do
  echo "Scaling down machine-approver..."
done
echo "Scaling up machine-approver..."
oc scale deployment -n openshift-cluster-machine-approver --replicas=1 machine-approver

# Wait a tiny bit, then list the csrs
sleep 5
oc get csr
# END Hack

wait_for_cvo_finish ocp
echo "Cluster up, you can interact with it via oc --config ${KUBECONFIG} <command>"
