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

case "${AGENT_E2E_TEST_BOOT_MODE}" in
  "PXE" )
    sudo pkill agentpxeserver || true
    rm -rf ${WORKING_DIR}/pxe
    ;;
esac

sudo podman rm -f extlb || true
sudo rm ${WORKING_DIR}/haproxy.* || true
sudo firewall-cmd --zone libvirt --remove-port=${MACHINE_CONFIG_SERVER_PORT}/tcp
sudo firewall-cmd --zone libvirt --remove-port=${KUBE_API_PORT}/tcp
sudo firewall-cmd --zone libvirt --remove-port=${INGRESS_ROUTER_PORT}/tcp