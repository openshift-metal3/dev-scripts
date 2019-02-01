#!/usr/bin/env bash
set -xe

source common.sh

ansible-playbook -b -vvv tripleo-quickstart-config/metalkube-teardown-playbook.yml -e @tripleo-quickstart-config/metalkube-nodes.yml -e local_working_dir=$HOME/.quickstart -e virthost=$HOSTNAME -e @config/environments/dev_privileged_libvirt.yml -i tripleo-quickstart-config/metalkube-inventory.ini
sudo rm -rf /etc/NetworkManager/dnsmasq.d/openshift.conf /etc/NetworkManager/conf.d/dnsmasq.conf
