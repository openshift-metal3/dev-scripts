#!/bin/bash

set -eu

# parse install-config.yaml
# takes two input
# bmctest.sh [-r release-image] in.yaml
# -r release-image
# defaults to the latest 4.13 if no -r supplied
RELEASEIMAGE=$(curl -s https://mirror.openshift.com/pub/openshift-v4/clients/ocp-dev-preview/latest-4.13/release.txt | grep -o 'quay.io/openshift-release-dev/ocp-release.*')


# upstream version will use a metal3 ironic image
IRONICIMAGE=$(podman run --rm $RELEASEIMAGE image ironic)

INPUTFILE=$(mktemp)
function cleanup(){
    rm -rf $INPUTFILE
}
trap "cleanup" EXIT


# Format of this might change before going upstream but for the moment lets use the hosts part of install-config.yaml
# TODO: may need other values from install-config.yaml e.g. externalBridge...
echo "hosts:" > $INPUTFILE
cat $1 | yq -y .platform.baremetal.hosts >> $INPUTFILE

$(dirname $0)/bmctest.sh -i $IRONICIMAGE $INPUTFILE
