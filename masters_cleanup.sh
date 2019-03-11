#!/usr/bin/bash

set -eux

pushd ocp/tf-master
terraform init  # in case plugin has changed
terraform destroy --auto-approve
popd
rm -rf ocp/tf-master
