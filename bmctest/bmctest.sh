#!/bin/bash

set -eu

# parse install-config.yaml
# takes two input
# bmctest.sh [-i ironic-image] in.yaml
# upstream version will use a metal3 ironic image

IRONICIMAGE="quay.io/metal3-io/ironic:latest"
if [ "$1" == "-i" ] ; then
    IRONICIMAGE=$2
    shift ; shift
fi
INPUTFILE=$1

CLEANUPFILE=
function cleanup(){
    if [ "$CLEANUPFILE" != "" ] ; then
        rm -rf $CLEANUPFILE
    fi
    sudo podman rm -f -t 0 bmctest || true
}
trap "cleanup" EXIT

### start ironic and httpd (maybe more in future
# starting everything inside a single container for now, if we choose to run bmctest
# from inside a container in future we'll have less to change
# TODO: will need to take pull secret as a input
sudo podman run --authfile /opt/dev-scripts/pull_secret.json --rm -d --net host --name bmctest --entrypoint sleep $IRONICIMAGE infinity
# starting ironic, (will need to setup env variables first)
sudo podman exec -d bmctest bash -c "runironic > /tmp/ironic"
# starting httpd
# ....

### for each node in install-config.yaml
for NODE in $(cat $INPUTFILE | yq .hosts[].name -r) ; do
    echo "== $NODE =="
    echo "Verifitying node credentials" # Can be done by just registering node with ironic
    echo "testing ability to power on/off node" # baremetal node power on X
    echo "testing vmedia attach" # may need to actually provision a live-iso image
    echo "verifying node boot device can be set"
    echo "testing vmedia detach" # may need to actually provision a live-iso image
done
