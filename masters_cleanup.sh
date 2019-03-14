#!/usr/bin/bash

set -eux

if [ -d ocp/tf-master ] ; then
    pushd ocp/tf-master
    terraform init  # in case plugin has changed
    terraform destroy --auto-approve
    popd
    rm -rf ocp/tf-master
fi
