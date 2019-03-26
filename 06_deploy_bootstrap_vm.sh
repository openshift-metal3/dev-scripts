#!/usr/bin/env bash
set -x
set -e

source ocp_install_env.sh
source common.sh
source utils.sh

if [ ! -d ocp ]; then
    mkdir -p ocp
    generate_ocp_install_config ocp
fi

# We are only doing this to generate the master ignition
# configs for patching later. This will go away when
# "create cluster" also launches the masters
create_cluster ocp
sleep 10

INFRA_ID=$(jq -r .infraID ocp/metadata.json)

while ! domain_net_ip ${INFRA_ID}-bootstrap baremetal; do
  echo "Waiting for ${INFRA_ID}-bootstrap interface to become active.."
  sleep 10
done

# NOTE: This is equivalent to the external API DNS record pointing the API to the API VIP
IP=$(domain_net_ip ${INFRA_ID}-bootstrap baremetal)
export API_VIP=$(dig +noall +answer "api.${CLUSTER_DOMAIN}" @$(network_ip baremetal) | awk '{print $NF}')
echo "address=/api.${CLUSTER_DOMAIN}/${API_VIP}" | sudo tee /etc/NetworkManager/dnsmasq.d/openshift.conf
export INGRESS_VIP=$(dig +noall +answer "ingress.${CLUSTER_DOMAIN}" @$(network_ip baremetal) | awk '{print $NF}')
echo "address=/.apps.${CLUSTER_DOMAIN}/${INGRESS_VIP}" | sudo tee -a /etc/NetworkManager/dnsmasq.d/openshift.conf
sudo systemctl reload NetworkManager

# Wait for ssh to start
$SSH -o ConnectionAttempts=500 core@$IP id

# Create a master_nodes.json file
jq '.nodes[0:3] | {nodes: .}' "${NODES_FILE}" | tee "${MASTER_NODES_FILE}"

echo "You can now ssh to \"$IP\" as the core user"
