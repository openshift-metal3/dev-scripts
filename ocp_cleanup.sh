#!/bin/bash
set -x

source logging.sh
source common.sh
source ocp_install_env.sh

sudo systemctl stop fix_certs.timer

if [ -d ocp ]; then
    ocp/openshift-install --dir ocp --log-level=debug destroy bootstrap
    ocp/openshift-install --dir ocp --log-level=debug destroy cluster
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
