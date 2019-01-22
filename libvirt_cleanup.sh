#!/usr/bin/env bash
set -xe

source common.sh

cp tripleo-quickstart-config/* ${HOME}/tripleo-quickstart/
cd ${HOME}/tripleo-quickstart
ansible-playbook -b -vvv metalkube-teardown-playbook.yml -e @metalkube-nodes.yml -e local_working_dir=$HOME/.quickstart -e virthost=$HOSTNAME -e @${HOME}/tripleo-quickstart/config/environments/dev_privileged_libvirt.yml -i metalkube-inventory.ini
