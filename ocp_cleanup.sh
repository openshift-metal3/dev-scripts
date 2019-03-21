#!/bin/bash
set -x

source common.sh
source ocp_install_env.sh

if [ -d ocp ]; then
    $GOPATH/src/github.com/openshift-metalkube/kni-installer/bin/kni-install --dir ocp --log-level=debug destroy bootstrap
    $GOPATH/src/github.com/openshift-metalkube/kni-installer/bin/kni-install --dir ocp --log-level=debug destroy cluster
    rm -rf ocp
fi

sudo rm -rf /etc/NetworkManager/dnsmasq.d/openshift.conf

# Cleanup ssh keys for baremetal network
if [ -f $HOME/.ssh/known_hosts ]; then
    sed -i "/^192.168.111/d" $HOME/.ssh/known_hosts
    sed -i "/^api.${CLUSTER_DOMAIN}/d" $HOME/.ssh/known_hosts
fi
