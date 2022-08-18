#!/usr/bin/env bash
set -x

source logging.sh
source common.sh
source utils.sh
source validation.sh

early_cleanup_validation

if [ -z "${METAL3_DEV_ENV}" ]; then
  export REPO_PATH=${WORKING_DIR}
  sync_repo_and_patch metal3-dev-env https://github.com/metal3-io/metal3-dev-env.git
fi

export ANSIBLE_FORCE_COLOR=true

ansible-playbook \
    -e @vm_setup_vars.yml \
    -e "ironic_prefix=${CLUSTER_NAME}_" \
    -e "cluster_name=${CLUSTER_NAME}" \
    -e "provisioning_network_name=${PROVISIONING_NETWORK_NAME}" \
    -e "baremetal_network_name=${BAREMETAL_NETWORK_NAME}" \
    -e "working_dir=$WORKING_DIR" \
    -e "num_masters=$NUM_MASTERS" \
    -e "num_workers=$NUM_WORKERS" \
    -e "num_extraworkers=$NUM_EXTRA_WORKERS" \
    -e "virthost=$HOSTNAME" \
    -e "manage_baremetal=$MANAGE_BR_BRIDGE" \
    -e "nodes_file=$NODES_FILE" \
    $ALMA_PYTHON_OVERRIDE \
    -i ${VM_SETUP_PATH}/inventory.ini \
    -b -vvv ${VM_SETUP_PATH}/teardown-playbook.yml

sudo rm -rf /etc/NetworkManager/dnsmasq.d/openshift-${CLUSTER_NAME}.conf /etc/yum.repos.d/delorean*
sudo rm -rf /etc/NetworkManager/conf.d/dnsmasq.conf
sudo rm -rf /etc/NetworkManager/dnsmasq.d/upstream.conf
if systemctl is-active --quiet NetworkManager; then
  sudo systemctl reload NetworkManager
else
  sudo systemctl restart NetworkManager
fi

# There was a bug in this file, it may need to be recreated.
# delete the interface as it can cause issues when not rebooting
if [ "$MANAGE_PRO_BRIDGE" == "y" ]; then
  sudo nmcli con del ${PROVISIONING_NETWORK_NAME}
fi

# Leaving this around causes issues when the host is rebooted
# delete the interface as it can cause issues when not rebooting
if [ "$MANAGE_BR_BRIDGE" == "y" ]; then
  sudo nmcli con del ${BAREMETAL_NETWORK_NAME}
fi

# Drop all ebtables rules
sudo ebtables --flush

# Kill any lingering proxy
sudo pkill -f oc.*proxy
