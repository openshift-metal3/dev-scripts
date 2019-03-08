#!/usr/bin/bash

set -eux
source utils.sh
source common.sh
source ocp_install_env.sh

export OS_TOKEN=fake-token
export OS_URL=http://localhost:6385/

# FIXME: this should just be "terraform delete"
nodes=$(openstack baremetal node list)
for node in $(jq -r .nodes[].name ${MASTER_NODES_FILE}); do
  if [[ $nodes =~ $node ]]; then
    openstack baremetal node undeploy $node --wait || true
    openstack baremetal node delete $node
  fi
done

rm -rf ocp/tf-master
