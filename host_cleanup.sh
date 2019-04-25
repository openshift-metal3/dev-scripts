#!/usr/bin/env bash
set -x

source logging.sh
source common.sh

ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e "working_dir=$WORKING_DIR" \
    -e "local_working_dir=$HOME/.quickstart" \
    -e "virthost=$HOSTNAME" \
    -e @tripleo-quickstart-config/metalkube-nodes.yml \
    -e @config/environments/dev_privileged_libvirt.yml \
    -i tripleo-quickstart-config/metalkube-inventory.ini \
    -b -vvv tripleo-quickstart-config/metalkube-teardown-playbook.yml

sudo rm -rf /etc/NetworkManager/dnsmasq.d/openshift.conf /etc/NetworkManager/conf.d/dnsmasq.conf
# There was a bug in this file, it may need to be recreated.
if [ "$MANAGE_PRO_BRIDGE" == "y" ]; then
    sudo rm -f /etc/sysconfig/network-scripts/ifcfg-provisioning
fi
sudo virsh net-list --name|grep -q baremetal
if [ "$?" == "0" ]; then
    sudo virsh net-destroy baremetal
    sudo virsh net-undefine baremetal
fi
sudo virsh net-list --name|grep -q provisioning
if [ "$?" == "0" ]; then
     sudo virsh net-destroy provisioning
     sudo virsh net-undefine provisioning
fi
