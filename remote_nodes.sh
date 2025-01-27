#!/bin/bash
set -xe

source logging.sh
source common.sh
source ocp_install_env.sh

ACTION=${1:-setup}
NS=${2:-openshift-machine-api}
IPTABLES=iptables

APPLY_REMOTE_NODES=${APPLY_REMOTE_NODES:-"true"}
REMOTE_CLUSTER_NAME=${REMOTE_CLUSTER_NAME:-"${CLUSTER_NAME}spoke"}
REMOTE_CLUSTER_NUM_MASTERS=${REMOTE_CLUSTER_NUM_MASTERS:-1}
REMOTE_CLUSTER_NUM_WORKERS=${REMOTE_CLUSTER_NUM_WORKERS:-0}
REMOTE_IP_STACK=${REMOTE_IP_STACK:-$IP_STACK}
REMOTE_CLUSTER_SUBNET_V4=${REMOTE_CLUSTER_SUBNET_V4:-"192.168.133.0/24"}
REMOTE_CLUSTER_SUBNET_V6=${REMOTE_CLUSTER_SUBNET_V6:-"fd2e:6f44:5dd8:c960::/120"}
REMOTE_NODE_BMC_DRIVER=redfish-virtualmedia
REMOTE_NODES_FILE=${REMOTE_NODES_FILE:-"${WORKING_DIR}/${CLUSTER_NAME}/remote_nodes.json"}
REMOTE_BAREMETALHOSTS_FILE=${REMOTE_BAREMETALHOSTS_FILE:-"${OCP_DIR}/remote_baremetalhosts.json"}
REMOTE_CLUSTER_DOMAIN="${NS}.${BASE_DOMAIN}"
REMOTE_MASTER_MEMORY=${REMOTE_MASTER_MEMORY:-$MASTER_MEMORY}
REMOTE_MASTER_DISK=${REMOTE_MASTER_DISK:-$MASTER_DISK}
REMOTE_MASTER_VCPU=${REMOTE_MASTER_VCPU:-$MASTER_VCPU}
REMOTE_WORKER_MEMORY=${REMOTE_WORKER_MEMORY:-$WORKER_MEMORY}
REMOTE_WORKER_DISK=${REMOTE_WORKER_DISK:-$WORKER_DISK}
REMOTE_WORKER_VCPU=${REMOTE_WORKER_VCPU:-$WORKER_VCPU}
REMOTE_EXTRA_WORKER_MEMORY=${REMOTE_EXTRA_WORKER_MEMORY:-$EXTRA_WORKER_MEMORY}
REMOTE_EXTRA_WORKER_DISK=${REMOTE_EXTRA_WORKER_DISK:-$EXTRA_WORKER_DISK}
REMOTE_EXTRA_WORKER_VCPU=${REMOTE_EXTRA_WORKER_VCPU:-$EXTRA_WORKER_VCPU}
REMOTE_VM_EXTRADISKS=${REMOTE_VM_EXTRADISKS:-$VM_EXTRADISKS}
REMOTE_VM_EXTRADISKS_LIST=${REMOTE_VM_EXTRADISKS_LIST:-$VM_EXTRADISKS_LIST}
REMOTE_VM_EXTRADISKS_SIZE=${REMOTE_VM_EXTRADISKS_SIZE:-$VM_EXTRADISKS_SIZE}
PROVISIONING_NETWORK_PROFILE=Disabled
VBMC_BASE_PORT=6250
TEARDOWN_PLAYBOOK=/tmp/${REMOTE_CLUSTER_NAME}-teardown-playbook.yml

if [[ "$REMOTE_IP_STACK" = "v4" ]]
then
	REMOTE_CLUSTER_SUBNET_V4=${REMOTE_CLUSTER_SUBNET_V4:-"192.168.133.0/24"}
	REMOTE_CLUSTER_SUBNET_V6=""
elif [[ "$REMOTE_IP_STACK" = "v6" ]]; then
	REMOTE_CLUSTER_SUBNET_V4=""
	REMOTE_CLUSTER_SUBNET_V6=${REMOTE_CLUSTER_SUBNET_V6:-"fd2e:6f44:5dd8:c960::/120"}
elif [[ "$REMOTE_IP_STACK" = "v4v6" ]]; then
	REMOTE_CLUSTER_SUBNET_V4=${REMOTE_CLUSTER_SUBNET_V4:-"192.168.133.0/24"}
	REMOTE_CLUSTER_SUBNET_V6=${REMOTE_CLUSTER_SUBNET_V6:-"fd2e:6f44:5dd8:c960::/120"}
else
	echo "Unexpected setting for REMOTE_IP_STACK: '${REMOTE_IP_STACK}'"
	exit 1
fi

function is_ocp_protected_namespace() {
  # Potential TODO(lranjbar): Add a check if the namespace is in an array. 
  # If we find an ocp protected namespace that doesn't start with openshift.
  # At the moment all of them seem to start with "openshift-"
  [[ $1 =~ ^openshift ]]
}

function playbook() {
	PLAYBOOK=${VM_SETUP_PATH}/setup-playbook.yml
	if [ "$1" == "cleanup" ]; then
		PLAYBOOK=${TEARDOWN_PLAYBOOK}

		# virtbmc teardown tears down *everything* which we don't want
		# Instead, we'll trick the playbook into doing nothing
		VIRTBMC_ACTION="ignore"
	fi

	ansible-playbook \
		-e @vm_setup_vars.yml \
		-e "ironic_prefix=${REMOTE_CLUSTER_NAME}_" \
		-e "cluster_name=${REMOTE_CLUSTER_NAME}" \
		-e "working_dir=$WORKING_DIR" \
		-e "libvirt_firmware=uefi" \
		-e "virthost=$HOSTNAME" \
		-e "vm_platform=$NODES_PLATFORM" \
		-e "provisioning_url_host=$PROVISIONING_URL_HOST" \
		-e "nodes_file=$REMOTE_NODES_FILE" \
		-e "vm_driver=$REMOTE_NODE_BMC_DRIVER" \
		-e "virtualbmc_base_port=$VBMC_BASE_PORT" \
		-e "virtbmc_action=$VIRTBMC_ACTION" \
		-e "master_hostname_format=$MASTER_HOSTNAME_FORMAT" \
    	-e "arbiter_hostname_format=$ARBITER_HOSTNAME_FORMAT" \
		-e "worker_hostname_format=$WORKER_HOSTNAME_FORMAT" \
		-e "provisioning_network_name=noprov" \
		-e "num_masters=$REMOTE_CLUSTER_NUM_MASTERS" \
		-e "num_workers=$REMOTE_CLUSTER_NUM_WORKERS" \
		-e "baremetal_network_name=$REMOTE_CLUSTER_NAME" \
		-e "baremetal_network_cidr_v4=$REMOTE_CLUSTER_SUBNET_V4" \
		-e "baremetal_network_cidr_v6=$REMOTE_CLUSTER_SUBNET_V6" \
		-e "forward_mode=nat" \
		-e "cluster_domain=$REMOTE_CLUSTER_DOMAIN" \
		-e "networks={{external_network}}" \
		-i ${VM_SETUP_PATH}/inventory.ini \
		-b -vvv ${PLAYBOOK}
}

function setup_remote_cluster() {
	playbook setup

	# Generate the assets for extra worker VMs
	cp -f ${REMOTE_NODES_FILE} ${REMOTE_NODES_FILE}.orig
	jq '.nodes' "${REMOTE_NODES_FILE}" | tee "${REMOTE_BAREMETALHOSTS_FILE}"

	generate_ocp_host_manifest ${OCP_DIR} ${REMOTE_BAREMETALHOSTS_FILE} remote_host_manifests.yaml ${NS}

	# Enable watchAllNamepaces flag in the provisioning-configuration resource
	oc patch provisioning provisioning-configuration --type merge -p '{"spec":{"watchAllNamespaces": true}}'

	# Enable traffic between ostestbm and ostest<NS>
	sudo $IPTABLES -I FORWARD 1 -o ${REMOTE_CLUSTER_NAME} -i ${BAREMETAL_NETWORK_NAME} -j ACCEPT

	# Create the NS and apply the manifests
	if [[ $APPLY_REMOTE_NODES = "true" ]]
	then
		# The default of $NS openshift-machine-api is a protected namespace
		if !(is_ocp_protected_namespace $NS)
		then
			oc create ns ${NS}
		fi
		oc apply -f ${OCP_DIR}/remote_host_manifests.yaml
	fi

}

function cleanup_remote_cluster() {
	# The default of $NS openshift-machine-api is a protected namespace
	if !(is_ocp_protected_namespace $NS)
	then
		oc delete ns ${NS}
	fi

	# Remove manifests
	rm -f ${OCP_DIR}/remote_host_manifests.yaml ${OCP_DIR}/${REMOTE_BAREMETALHOSTS_FILE} ${REMOTE_NODES_FILE}

	# Run a partial teardown playbook. We don't want a full virtualbmc teardown.
	cat > ${TEARDOWN_PLAYBOOK} <<EOF
---
- name: Teardown previous libvirt setup
  hosts: virthost
  connection: local
  gather_facts: true
  tasks:
    - import_role:
        name: common
    - import_role:
        name: libvirt
      vars:
        libvirt_action: "teardown"
EOF

	playbook cleanup
	rm -f ${TEARDOWN_PLAYBOOK}

	# Remove the iptables rule between ostestbm and ostest<NS>
	sudo $IPTABLES -C FORWARD -o ${REMOTE_CLUSTER_NAME} -i ${BAREMETAL_NETWORK_NAME} -j ACCEPT  >/dev/null 2>&1
	if [ $? -ne 0 ]; then
		sudo $IPTABLES -D FORWARD -o ${REMOTE_CLUSTER_NAME} -i ${BAREMETAL_NETWORK_NAME} -j ACCEPT
	fi
}

if [ "$ACTION" == "setup" ]; then
	setup_remote_cluster
elif [ "$ACTION" == "cleanup" ]; then
	cleanup_remote_cluster
else
	echo "Unknown action: $ACTION"
	echo "Usage: $0 <setup|cleanup> [namespace]."
	exit 1
fi
