#!/usr/bin/bash

set -eux
source utils.sh
source common.sh
source ocp_install_env.sh

# Note This logic will likely run in a container (on the bootstrap VM)
# for the final solution, but for now we'll prototype the workflow here
export OS_TOKEN=fake-token
export OS_URL=http://localhost:6385/

wait_for_json ironic \
    "${OS_URL}/v1/nodes" \
    10 \
    -H "Accept: application/json" -H "Content-Type: application/json" -H "User-Agent: wait-for-json" -H "X-Auth-Token: $OS_TOKEN"

# Clean previously env
nodes=$(openstack baremetal node list)
for node in $(jq -r .nodes[].name ${MASTER_NODES_FILE}); do
  if [[ $nodes =~ $node ]]; then
    openstack baremetal node undeploy $node --wait || true
    openstack baremetal node delete $node
  fi
done

openstack baremetal create $MASTER_NODES_FILE
mkdir -p configdrive/openstack/latest
cp ocp/master.ign configdrive/openstack/latest/user_data
for node in $(jq -r .nodes[].name $MASTER_NODES_FILE); do

  # FIXME(shardy) we should parameterize the image
  openstack baremetal node set $node --instance-info "image_source=http://172.22.0.1/images/$RHCOS_IMAGE_FILENAME_LATEST" --instance-info image_checksum=$(curl http://172.22.0.1/images/$RHCOS_IMAGE_FILENAME_LATEST.md5sum) --instance-info root_gb=25 --property root_device="{\"name\": \"$ROOT_DISK\"}"
  openstack baremetal node manage $node --wait
  openstack baremetal node provide $node --wait
done

for node in $(jq -r .nodes[].name $MASTER_NODES_FILE); do
  openstack baremetal node deploy --config-drive configdrive $node
done

# Note we have to tolerate failure with the || echo 0 due to this issue
# https://storyboard.openstack.org/#!/story/2005093
NUM_ACTIVE=$(openstack baremetal node list --fields name --fields provision_state | grep master | grep active | wc -l || echo 0)
while [ "$NUM_ACTIVE" != "3" ]; do
  if openstack baremetal node list --fields name --fields provision_state | grep master | grep error; then
    openstack baremetal node list
    echo "Error detected waiting for baremetal nodes to become active" >&2
    exit 1
  fi
  sleep 10
  NUM_ACTIVE=$(openstack baremetal node list --fields name --fields provision_state | grep master | grep active | wc -l || echo 0)
done

echo "Master nodes active"
openstack baremetal node list

NUM_LEASES=$(sudo virsh net-dhcp-leases baremetal | grep master | wc -l)
while [ "$NUM_LEASES" -ne 3 ]; do
  sleep 10
  NUM_LEASES=$(sudo virsh net-dhcp-leases baremetal | grep master | wc -l)
done

echo "Master nodes up, you can ssh to the following IPs with core@<IP>"
sudo virsh net-dhcp-leases baremetal

while [[ ! $(ssh -o StrictHostKeyChecking=no "core@api.${CLUSTER_NAME}.${BASE_DOMAIN}" hostname) =~ master- ]]; do
  echo "Waiting for the master API to become ready..."
  sleep 10
done

NODES_ACTIVE=$(oc --config ocp/auth/kubeconfig get nodes | grep "master-[0-2] *Ready" | wc -l)
while [ "$NODES_ACTIVE" -ne 3 ]; do
  sleep 10
  NODES_ACTIVE=$(oc --config ocp/auth/kubeconfig get nodes | grep "master-[0-2] *Ready" | wc -l)
done
oc --config ocp/auth/kubeconfig get nodes
echo "Cluster up, you can interact with it via oc --config ocp/auth/kubeconfig <command>"
