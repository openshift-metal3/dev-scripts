#!/usr/bin/env bash
set -x
set -e

source common.sh
source ocp_install_env.sh
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

# NOTE: This is equivalent to the external API DNS record pointing the API to the API VIP
if [ "$MANAGE_BR_BRIDGE" == "y" ] ; then
    export API_VIP=$(dig +noall +answer "api.${CLUSTER_DOMAIN}" @$(network_ip baremetal) | awk '{print $NF}')
else
    export API_VIP=$(dig +noall +answer "api.${CLUSTER_DOMAIN}"  | awk '{print $NF}')
fi
echo "address=/api.${CLUSTER_DOMAIN}/${API_VIP}" | sudo tee /etc/NetworkManager/dnsmasq.d/openshift.conf
sudo systemctl reload NetworkManager

# Wait for ssh to start
$SSH -o ConnectionAttempts=$BOOTSTRAP_SSH_READY core@$API_VIP id

# Create a master_nodes.json file
jq '.nodes[0:3] | {nodes: .}' "${NODES_FILE}" | tee "${MASTER_NODES_FILE}"

echo "You can now ssh to \"$API_VIP\" as the core user"
