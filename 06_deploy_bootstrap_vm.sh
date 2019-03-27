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

# NOTE: This is equivalent to the external API DNS record pointing the API to the API VIP
if [ "$NODES_PLATFORM" == 'libvirt' ]; then
  export API_VIP=$(dig +noall +answer "api.${CLUSTER_DOMAIN}" @$(network_ip baremetal) | awk '{print $NF}')
  echo "address=/api.${CLUSTER_DOMAIN}/${API_VIP}" | sudo tee /etc/NetworkManager/dnsmasq.d/openshift.conf
  sudo systemctl reload NetworkManager
else
  export API_VIP=$(dig +short "api.${CLUSTER_DOMAIN}")
fi

# Wait for ssh to start
$SSH -o ConnectionAttempts=$BOOTSTRAP_SSH_READY core@$API_VIP id

# Register bootstrap VM baremetal nic address
IP=$($SSH core@$API_VIP "/usr/sbin/ip -o -4 a show eth0" | awk '/brd/ {print $4}' | awk -F '/' '{print $1}')

# Create a master_nodes.json file
jq '.nodes[0:3] | {nodes: .}' "${NODES_FILE}" | tee "${MASTER_NODES_FILE}"

echo "You can now ssh to \"$IP\" as the core user"
