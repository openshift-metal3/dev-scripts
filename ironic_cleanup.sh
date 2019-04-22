#!/bin/bash

function wait_condition () {
condition=0
while [ "$condition" != "3" ] ; do
  condition=$( openstack baremetal node list -c 'Provisioning State' | grep $1 | wc -l)
  echo "waiting 5s for servers to be $1"
  sleep 5
done
}

export OS_TOKEN=fake-token
export OS_URL=http://localhost:6385/

SERVERS=`openstack baremetal node list -f value -c Name| xargs`
if [ -z "$SERVERS" ] ; then
    echo "nothing to do"
    exit 0
fi
for server in $SERVERS ; do openstack baremetal node undeploy $server ; done
wait_condition "available"
for server in $SERVERS ; do openstack baremetal node manage $server ; done
for server in $SERVERS ; do openstack baremetal node clean --clean-steps '[{"interface": "deploy", "step": "erase_devices_metadata"}]' $server ; done
wait_condition "manageable"
for server in $SERVERS ; do openstack baremetal node delete $server ; done
