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

if [[ "${AGENT_E2E_TEST_BOOT_MODE}" == "DISKIMAGE" ]]; then
    sudo rm -rf "${OCP_DIR}/cache"
    sudo rm -rf "${OCP_DIR}/temp"
    sudo podman rmi -f ${APPLIANCE_IMAGE} || true
fi

if [[ -n ${BOOT_SERVER_DIR:-} && -d ${BOOT_SERVER_DIR} ]]; then
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
