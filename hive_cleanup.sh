#!/usr/bin/env bash
set -xe

source logging.sh
source common.sh
source utils.sh
source ocp_install_env.sh
source hive_common.sh

# Delete the hive1 cluster resources.

override_vars_for_hive 1

ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e @vm_setup_vars.yml \
    -e @hive_vars.yml \
    -e "provisioning_network_name=hive1prov" \
    -e "baremetal_network_name=hive1bm" \
    -e "working_dir=$WORKING_DIR" \
    -e "num_masters=$HIVE1_NUM_MASTERS" \
    -e "num_workers=$HIVE1_NUM_WORKERS" \
    -e "extradisks=$VM_EXTRADISKS" \
    -e "virthost=$HOSTNAME" \
    -e "manage_baremetal=y" \
    -e "ironic_prefix=hive1_" \
    -i ${VM_SETUP_PATH}/inventory.ini \
    -b -vvv ${VM_SETUP_PATH}/teardown-playbook.yml

sudo rm -rf /etc/NetworkManager/dnsmasq.d/openshift.conf /etc/NetworkManager/conf.d/dnsmasq.conf /etc/yum.repos.d/delorean*
# There was a bug in this file, it may need to be recreated.
# delete the interface as it can cause issues when not rebooting
sudo ifdown hive1prov || true
sudo ip link delete hive1prov || true
sudo rm -f /etc/sysconfig/network-scripts/ifcfg-hive1prov

# Leaving this around causes issues when the host is rebooted
# delete the interface as it can cause issues when not rebooting
sudo ifdown hive1bm || true
sudo ip link delete hive1bm || true
sudo rm -f /etc/sysconfig/network-scripts/ifcfg-hive1bm


# Delete the hive2 cluster resources.

override_vars_for_hive 2

ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e @vm_setup_vars.yml \
    -e @hive_vars.yml \
    -e "provisioning_network_name=hive2prov" \
    -e "baremetal_network_name=hive2bm" \
    -e "working_dir=$WORKING_DIR" \
    -e "num_masters=$HIVE2_NUM_MASTERS" \
    -e "num_workers=$HIVE2_NUM_WORKERS" \
    -e "extradisks=$VM_EXTRADISKS" \
    -e "virthost=$HOSTNAME" \
    -e "manage_baremetal=y" \
    -e "ironic_prefix=hive2_" \
    -i ${VM_SETUP_PATH}/inventory.ini \
    -b -vvv ${VM_SETUP_PATH}/teardown-playbook.yml

sudo rm -rf /etc/NetworkManager/dnsmasq.d/openshift.conf /etc/NetworkManager/conf.d/dnsmasq.conf /etc/yum.repos.d/delorean*
# There was a bug in this file, it may need to be recreated.
# delete the interface as it can cause issues when not rebooting
sudo ifdown hive2prov || true
sudo ip link delete hive2prov || true
sudo rm -f /etc/sysconfig/network-scripts/ifcfg-hive2prov

# Leaving this around causes issues when the host is rebooted
# delete the interface as it can cause issues when not rebooting
sudo ifdown hive2bm || true
sudo ip link delete hive2bm || true
sudo rm -f /etc/sysconfig/network-scripts/ifcfg-hive2bm
