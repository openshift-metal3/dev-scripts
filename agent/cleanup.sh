#!/usr/bin/env bash
set -x

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR=${SCRIPTDIR}/logs
source $SCRIPTDIR/logging.sh
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/utils.sh
source $SCRIPTDIR/validation.sh
source $SCRIPTDIR/agent/common.sh

early_cleanup_validation

rm -rf "${OCP_DIR}/manifests"
rm -rf "${OCP_DIR}/output"

function agent_remove_iscsi_disks() {
    for (( n=0; n<${2}; n++ ))
      do
          iscsi_disk=${SCRIPTDIR}/"iscsi-${1}-${n}"
          sudo rm -f ${iscsi_disk}
      done
}

if [[ "${AGENT_E2E_TEST_BOOT_MODE}" == "DISKIMAGE" ]]; then
    sudo rm -rf "${OCP_DIR}/cache"
    sudo rm -rf "${OCP_DIR}/temp"
    sudo podman rmi -f ${APPLIANCE_IMAGE} || true
fi

if [[ -d ${BOOT_SERVER_DIR} ]]; then
   sudo pkill agentpxeserver || true
   rm -rf ${BOOT_SERVER_DIR}
fi

sudo podman rm -f extlb || true
sudo rm ${WORKING_DIR}/haproxy.* || true
sudo firewall-cmd --zone libvirt --remove-port=${MACHINE_CONFIG_SERVER_PORT}/tcp
sudo firewall-cmd --zone libvirt --remove-port=${KUBE_API_PORT}/tcp
sudo firewall-cmd --zone libvirt --remove-port=${INGRESS_ROUTER_PORT}/tcp

if [[ $NUM_MASTERS == 1 && $IP_STACK == "v6" ]]; then
    sudo sed -i "/${AGENT_NODE0_IPSV6} console-openshift-console.apps.${CLUSTER_DOMAIN}/d" /etc/hosts
    sudo sed -i "/${AGENT_NODE0_IPSV6} oauth-openshift.apps.${CLUSTER_DOMAIN}/d" /etc/hosts
    sudo sed -i "/${AGENT_NODE0_IPSV6} thanos-querier-openshift-monitoring.apps.${CLUSTER_DOMAIN}/d" /etc/hosts
fi

if [[ "${AGENT_E2E_TEST_BOOT_MODE}" == "ISCSI" ]]; then
    # Remove network created for ISCSI
    iscsi_network=$(sudo virsh net-list)
    if echo ${iscsi_network} | grep -q "${ISCSI_NETWORK}"; then
        sudo virsh net-destroy ${ISCSI_NETWORK}
    fi

    iscsi_inactive=$(sudo virsh net-list --inactive)
    if echo ${iscsi_inactive} | grep -q "${ISCSI_NETWORK}"; then
       sudo virsh net-undefine ${ISCSI_NETWORK}
    fi

    # Remove ISCSI targets
    if [[ -x "$(command -v targetcli)" ]] ; then
        sudo targetcli clearconfig confirm=True
    fi

    agent_remove_iscsi_disks master $NUM_MASTERS
    agent_remove_iscsi_disks worker $NUM_WORKERS
fi

if sudo buildah images --storage-driver vfs | grep -q "localhost/appliance-test"; then
    sudo buildah rmi -f --storage-driver vfs localhost/appliance-test
fi
