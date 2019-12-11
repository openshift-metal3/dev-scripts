#!/usr/bin/env bash
set -x

source logging.sh
source common.sh
source utils.sh

if [ -z "${METAL3_DEV_ENV}" ]; then
  export REPO_PATH=${WORKING_DIR}
  sync_repo_and_patch metal3-dev-env https://github.com/metal3-io/metal3-dev-env.git
fi

ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e @vm_setup_vars.yml \
    -e "working_dir=$WORKING_DIR" \
    -e "num_masters=$NUM_MASTERS" \
    -e "num_workers=$NUM_WORKERS" \
    -e "extradisks=$VM_EXTRADISKS" \
    -e "virthost=$HOSTNAME" \
    -e "manage_baremetal=$MANAGE_BR_BRIDGE" \
    -i ${VM_SETUP_PATH}/inventory.ini \
    -b -vvv ${VM_SETUP_PATH}/teardown-playbook.yml

if sudo virsh list --all | grep -q openshift2; then
  source ocp_install_env2.sh
  ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e @vm_setup_vars.yml \
    -e @openshift_2_vars.yml \
    -e "working_dir=${WORKING_DIR}" \
    -e "virtualbmc_base_port=$VBMC_BASE_PORT" \
    -e "num_masters=$NUM_MASTERS2" \
    -e "num_workers=$NUM_WORKERS2" \
    -e "extradisks=$VM_EXTRADISKS" \
    -e "virthost=$HOSTNAME" \
    -e "vm_platform=$NODES_PLATFORM" \
    -e "manage_baremetal=$MANAGE_BR_BRIDGE" \
    -e "ironic_prefix=openshift2_" \
    -i ${VM_SETUP_PATH}/inventory.ini \
    -b -vvv ${VM_SETUP_PATH}/teardown-playbook.yml

  if [ "$MANAGE_BR_BRIDGE" == "y" ]; then
    sudo ifdown baremetal2 || true
    sudo ip link delete baremetal2 || true
    sudo rm -f /etc/sysconfig/network-scripts/ifcfg-baremetal2
  fi
fi

sudo rm -rf /etc/NetworkManager/dnsmasq.d/openshift.conf /etc/NetworkManager/conf.d/dnsmasq.conf
# There was a bug in this file, it may need to be recreated.
# delete the interface as it can cause issues when not rebooting
if [ "$MANAGE_PRO_BRIDGE" == "y" ]; then
    sudo ifdown provisioning || true
    sudo ip link delete provisioning || true
    sudo rm -f /etc/sysconfig/network-scripts/ifcfg-provisioning
fi
# Leaving this around causes issues when the host is rebooted
# delete the interface as it can cause issues when not rebooting
if [ "$MANAGE_BR_BRIDGE" == "y" ]; then
    sudo ifdown baremetal || true
    sudo ip link delete baremetal || true
    sudo rm -f /etc/sysconfig/network-scripts/ifcfg-baremetal
fi
# Kill any lingering proxy
sudo pkill -f oc.*proxy
