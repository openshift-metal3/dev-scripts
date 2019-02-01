#!/bin/bash

set -e

source ocp_install_env.sh

$GOPATH/src/github.com/openshift/installer/bin/openshift-install --log-level=debug --dir ocp destroy cluster

rm -rf ocp/{auth,terraform.tfstate}

sudo rm -rf /etc/NetworkManager/dnsmasq.d/openshift.conf
