#!/usr/bin/bash

set -eux
source utils.sh
source common.sh

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
  openstack baremetal node set $node --instance-info image_source=http://172.22.0.1/images/redhat-coreos-maipo-47.284-openstack_dualdhcp.qcow2 --instance-info image_checksum=$(md5sum $IRONIC_DATA_DIR/html/images/redhat-coreos-maipo-47.284-openstack_dualdhcp.qcow2 | awk '{print $1}') --instance-info root_gb=25 --property root_device="{\"name\": \"$ROOT_DISK\"}"
  openstack baremetal node manage $node --wait
  openstack baremetal node provide $node --wait
done

for node in $(jq -r .nodes[].name $MASTER_NODES_FILE); do
  openstack baremetal node deploy --config-drive configdrive $node
done
# FIXME(shardy) we should wait for the node deploy to complete (or fail)
