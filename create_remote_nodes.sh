#!/bin/bash
set -xe

source logging.sh
source common.sh
source ocp_install_env.sh

namespace=$1
if [ $namespace == "" ]; then
	namespace=openshift-machine-api
fi

export REMOTE_CLUSTER_NAME=${REMOTE_CLUSTER_NAME:-${CLUSTER_NAME}rc}
export REMOTE_CLUSTER_NUM_MASTERS=${REMOTE_CLUSTER_NUM_MASTERS:-1}
export REMOTE_CLUSTER_NUM_WORKERS=${REMOTE_CLUSTER_NUM_WORKERS:-0}
export REMOTE_CLUSTER_SUBNET_V4=${REMOTE_CLUSTER_SUBNET_V4:-"192.168.133.0/24"}
export REMOTE_CLUSTER_SUBNET_V6=${REMOTE_CLUSTER_SUBNET_V6:-"fd2e:6f44:5dd8:c960::/120"}
export REMOTE_NODE_BMC_DRIVER=redfish-virtualmedia
export REMOTE_NODES_FILE=${REMOTE_NODES_FILE:-"${WORKING_DIR}/${CLUSTER_NAME}/remote_nodes.json"}
export REMOTE_BAREMETALHOSTS_FILE=${REMOTE_BAREMETALHOSTS_FILE:-"${OCP_DIR}/remote_baremetalhosts.json"}
export PROVISIONING_NETWORK_PROFILE=Disabled
export MANAGE_BR_BRIDGE=y

ansible-playbook \
    -e @vm_setup_vars.yml \
    -e "ironic_prefix=${REMOTE_CLUSTER_NAME}_" \
    -e "cluster_name=${REMOTE_CLUSTER_NAME}" \
    -e "working_dir=$WORKING_DIR" \
    -e "extradisks=$VM_EXTRADISKS" \
    -e "libvirt_firmware=uefi" \
    -e "virthost=$HOSTNAME" \
    -e "vm_platform=$NODES_PLATFORM" \
    -e "provisioning_url_host=$PROVISIONING_URL_HOST" \
    -e "nodes_file=$REMOTE_NODES_FILE" \
    -e "vm_driver=$REMOTE_NODE_BMC_DRIVER" \
    -e "virtualbmc_base_port=$VBMC_BASE_PORT" \
    -e "master_hostname_format=$MASTER_HOSTNAME_FORMAT" \
    -e "worker_hostname_format=$WORKER_HOSTNAME_FORMAT" \
    -e "provisioning_network_name=noprov" \
    -e "num_masters=$REMOTE_CLUSTER_NUM_MASTERS" \
    -e "num_workers=$REMOTE_CLUSTER_NUM_WORKERS" \
    -e "baremetal_network_name=$REMOTE_CLUSTER_NAME" \
    -e "baremetal_network_cidr_v4=$REMOTE_CLUSTER_SUBNET_V4" \
    -e "baremetal_network_cidr_v6=$REMOTE_CLUSTER_SUBNET_V6" \
    -i ${VM_SETUP_PATH}/inventory.ini \
    -b -vvv ${VM_SETUP_PATH}/setup-playbook.yml

# Generate the assets for extra worker VMs
cp -f ${REMOTE_NODES_FILE} ${REMOTE_NODES_FILE}.orig
jq '.nodes' "${REMOTE_NODES_FILE}" | tee "${REMOTE_BAREMETALHOSTS_FILE}"

generate_ocp_host_manifest ${OCP_DIR} ${REMOTE_BAREMETALHOSTS_FILE} remote_host_manifests.yaml ${namespace}
