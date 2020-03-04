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
    -e "provisioning_network_name=${PROVISIONING_NETWORK_NAME}" \
    -e "baremetal_network_name=${BAREMETAL_NETWORK_NAME}" \
    -e "working_dir=$WORKING_DIR" \
    -e "num_masters=$NUM_MASTERS" \
    -e "num_workers=$NUM_WORKERS" \
    -e "extradisks=$VM_EXTRADISKS" \
    -e "virthost=$HOSTNAME" \
    -e "manage_baremetal=$MANAGE_BR_BRIDGE" \
    -i ${VM_SETUP_PATH}/inventory.ini \
    -b -vvv ${VM_SETUP_PATH}/teardown-playbook.yml

sudo rm -rf /etc/NetworkManager/dnsmasq.d/openshift-${CLUSTER_NAME}.conf /etc/yum.repos.d/delorean*
# There was a bug in this file, it may need to be recreated.
# delete the interface as it can cause issues when not rebooting
if [ "$MANAGE_PRO_BRIDGE" == "y" ]; then
    sudo ifdown ${PROVISIONING_NETWORK_NAME} || true
    sudo ip link delete ${PROVISIONING_NETWORK_NAME} || true
    sudo rm -f /etc/sysconfig/network-scripts/ifcfg-${PROVISIONING_NETWORK_NAME}
fi
# Leaving this around causes issues when the host is rebooted
# delete the interface as it can cause issues when not rebooting
if [ "$MANAGE_BR_BRIDGE" == "y" ]; then
    sudo ifdown ${BAREMETAL_NETWORK_NAME} || true
    sudo ip link delete ${BAREMETAL_NETWORK_NAME} || true
    sudo rm -f /etc/sysconfig/network-scripts/ifcfg-${BAREMETAL_NETWORK_NAME}
fi
# Kill any lingering proxy
sudo pkill -f oc.*proxy
