#!/bin/bash

set -x

source ocp_install_env.sh

virsh destroy "${CLUSTER_NAME}-bootstrap"
virsh undefine "${CLUSTER_NAME}-bootstrap" --remove-all-storage
VOL_POOL=$(virsh vol-pool "/var/lib/libvirt/images/${CLUSTER_NAME}-bootstrap.ign")
virsh vol-delete "${CLUSTER_NAME}-bootstrap.ign" --pool "${VOL_POOL}"
rm -rf ocp
sudo rm -rf /etc/NetworkManager/dnsmasq.d/openshift.conf

# Cleanup ssh keys for baremetal network
sed -i "/^192.168.111/d" /home/$USER/.ssh/known_hosts
sed -i "/^api.${CLUSTER_DOMAIN}/d" /home/$USER/.ssh/known_hosts
