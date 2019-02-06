#!/usr/bin/env bash
set -x
set -e

export OS_TOKEN=fake-token
export OS_URL=http://ostest-api.test.metalkube.org:6385/

rm -rf configdrive/openstack/latest || true
mkdir -p configdrive/openstack/latest
cp ocp/master.ign configdrive/openstack/latest/user_data

sudo ip r del 172.22.0.0/24 || true
sudo ip route add 172.22.0.0/24 via $(getent hosts ostest-api.test.metalkube.org| grep 192 | awk '{ print $1 }')

openstack baremetal create ocp/master_nodes.json

for i in 0 1 2; do
    # Set NODE_UUID to the uuid of the node you want to work with
    NODE_UUID=$(openstack baremetal node show openshift-master-$i -f value -c uuid)
    openstack baremetal node set $NODE_UUID --instance-info image_source=http://172.22.0.1/images/redhat-coreos-maipo-47.284-openstack.qcow2 --instance-info image_checksum=2a38fafe0b9465937955e4d054b8db3a --instance-info root_gb=25 --property root_device='{"name": "/dev/vda"}'
    openstack baremetal node manage $NODE_UUID --wait
    openstack baremetal node provide $NODE_UUID --wait
    openstack baremetal node deploy --config-drive configdrive $NODE_UUID
done

for i in 0 1 2; do
    while ! ssh -o "StrictHostKeyChecking=no" core@"ostest-etcd-$i.test.metalkube.org" id ; do sleep 5 ; done
done
