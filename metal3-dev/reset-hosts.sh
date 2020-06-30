#!/bin/bash

set -ex

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

bmo_path=$GOPATH/src/github.com/metal3-io/baremetal-operator
if [ ! -d $bmo_path ]; then
    echo "Did not find $bmo_path" 1>&2
    exit 1
fi

hosts=$(oc get baremetalhost -n openshift-machine-api -o name | cut -f2 -d/)

(pushd $bmo_path &&
     go run ./cmd/reset-host/main.go -n openshift-machine-api $hosts)

# The openstack command depends on having OS_CLOUD set. Set it to a
# reasonable default for clusters built with dev-scripts, while
# allowing the user to override it if they built their cluster some
# other way (such as with the assisted installer).
export OS_CLOUD=${OS_CLOUD:-metal3}

# Move to the dev-scripts directory so we have a clouds.yaml file.
pushd "${SCRIPTDIR}"

for host in $hosts; do
    openstack baremetal node maintenance set $host || continue
done
openstack baremetal node delete $hosts
