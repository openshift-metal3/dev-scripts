#!/usr/bin/env bash
set -x

source common.sh

# Kill and remove the running ironic
for name in ironic ironic-inspector ; do 
    sudo podman ps | grep -w "$name$" && sudo podman kill $name
    sudo podman ps --all | grep -w "$name$" && sudo podman rm $name
done

ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e "working_dir=$WORKING_DIR" \
    -e "local_working_dir=$HOME/.quickstart" \
    -e "virthost=$HOSTNAME" \
    -e @tripleo-quickstart-config/metalkube-nodes.yml \
    -e @config/environments/dev_privileged_libvirt.yml \
    -i tripleo-quickstart-config/metalkube-inventory.ini \
    -b -vvv tripleo-quickstart-config/metalkube-teardown-playbook.yml

sudo rm -rf /etc/NetworkManager/dnsmasq.d/openshift.conf /etc/NetworkManager/conf.d/dnsmasq.conf
sudo virsh net-destroy baremetal
sudo virsh net-undefine baremetal
