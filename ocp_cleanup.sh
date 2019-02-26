#!/bin/bash

set -x

source ocp_install_env.sh

sudo virsh destroy "${CLUSTER_NAME}-bootstrap"
sudo virsh undefine "${CLUSTER_NAME}-bootstrap" --remove-all-storage
VOL_POOL=$(sudo virsh vol-pool "/var/lib/libvirt/images/${CLUSTER_NAME}-bootstrap.ign")
sudo virsh vol-delete "${CLUSTER_NAME}-bootstrap.ign" --pool "${VOL_POOL}"
rm -rf ocp
sudo rm -rf /etc/NetworkManager/dnsmasq.d/openshift.conf

# Cleanup ssh keys for baremetal network
sed -i "/^192.168.111/d" /home/$USER/.ssh/known_hosts
