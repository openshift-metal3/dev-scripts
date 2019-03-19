#!/usr/bin/bash

# FIXME - what are the prerequisites we need to wait for here, is waiting for 
# bootstrap complete enough?

# These will ultimately be deployed via kni-installer to the bootstrap node
# where they will then be applied to the cluster, but for now we do it
# manually
cd manifests
for manifest in $(ls -1 *.yaml | sort -h); do
  oc --as system:admin --config ../ocp/auth/kubeconfig apply -f ${manifest}
  echo "manifests/${manifest} applied"
done
