#!/usr/bin/env bash
set -xe

source common.sh

# This script will create some libvirt VMs do act as "dummy baremetal"
# then configure python-virtualbmc to control them - these can later
# be deployed via the install process similar to how we test TripleO
# Note we copy the playbook so the roles/modules from tripleo-quickstart
# are found without a special ansible.cfg
cp tripleo-quickstart-config/* ${HOME}/tripleo-quickstart/
cd ${HOME}/tripleo-quickstart
sed -i "s/VIRTHOST_HOSTNAME/$HOSTNAME/" metalkube-inventory.ini
ansible-playbook -b -vvv metalkube-setup-playbook.yml -e @metalkube-nodes.yml -e local_working_dir=$HOME/.quickstart -e virthost=$HOSTNAME -e @${HOME}/tripleo-quickstart/config/environments/dev_privileged_libvirt.yml -i metalkube-inventory.ini
