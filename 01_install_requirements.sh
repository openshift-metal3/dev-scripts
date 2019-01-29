#!/usr/bin/env bash
set -ex

source common.sh

# FIXME ocp-doit required this so leave permissive for now
sudo setenforce permissive
sudo sed -i "s/=enforcing/=permissive/g" /etc/selinux/config
sudo yum -y update

sudo yum -y install epel-release --enablerepo=extras
sudo yum -y install curl vim-enhanced wget python-pip patch psmisc figlet golang

sudo pip install lolcat

# for tripleo-repos install
sudo yum -y install python-setuptools python-requests

if [ ! -f $HOME/openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit.tar.gz ]; then
  cd
  wget https://github.com/openshift/origin/releases/download/v3.11.0/openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit.tar.gz
  tar xvzf openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit.tar.gz
  sudo cp openshift-origin-client-tools-v3.11.0-0cbc58b-linux-64bit/{kubectl,oc} /usr/local/bin/
fi

# We're reusing some tripleo pieces for this setup so clone them here
cd
if [ ! -d tripleo-repos ]; then
  git clone https://git.openstack.org/openstack/tripleo-repos
fi
pushd tripleo-repos
sudo python setup.py install
popd

# Needed to get a recent python-virtualbmc package
sudo tripleo-repos current-tripleo

# Work around a conflict with a newer zeromq from epel
if ! grep -q zeromq /etc/yum.repos.d/epel.repo; then
  sudo sed -i '/enabled=1/a exclude=zeromq*' /etc/yum.repos.d/epel.repo
fi
sudo yum -y update

# make sure additional requirments are installed
sudo yum install -y bind-utils ansible python-netaddr python-virtualbmc libvirt libvirt-devel libvirt-daemon-kvm qemu-kvm virt-install jq

if [ ! -f $HOME/.ssh/id_rsa.pub ]; then
    ssh-keygen
fi

# root needs a private key to talk to libvirt, see configure-vbmc.yml
if sudo [ ! -f /root/.ssh/id_rsa_virt_power ]; then
    sudo ssh-keygen -f /root/.ssh/id_rsa_virt_power -P ""
    sudo cat /root/.ssh/id_rsa_virt_power.pub | sudo tee -a /root/.ssh/authorized_keys
fi
