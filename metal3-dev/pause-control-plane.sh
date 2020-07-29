#!/bin/bash -x

for host in $(oc get baremetalhost -n openshift-machine-api -o name | grep -e '-master-'); do
    oc annotate --overwrite -n openshift-machine-api "$host" \
       'baremetalhost.metal3.io/paused=""'
done
