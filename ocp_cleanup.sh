#!/bin/bash
set -x

source logging.sh
source common.sh
source ocp_install_env.sh

sudo systemctl stop fix_certs.timer
systemctl is-failed fix_certs.service >/dev/null && sudo systemctl reset-failed fix_certs.service

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

if test -f assets/templates/99_master-chronyd-redhat.yaml ; then
    rm -f assets/templates/99_master-chronyd-redhat.yaml
fi
if test -f assets/templates/99_worker-chronyd-redhat.yaml ; then
    rm -f assets/templates/99_worker-chronyd-redhat.yaml
fi
