#!/usr/bin/env bash
set -x

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR="${SCRIPTDIR}/logs"
source "$SCRIPTDIR/logging.sh"
source "$SCRIPTDIR/common.sh"
source "$SCRIPTDIR/utils.sh"
source "$SCRIPTDIR/validation.sh"
source "$SCRIPTDIR/agent/common.sh"

early_cleanup_validation

rm -rf "${OCP_DIR}/manifests"
rm -rf "${OCP_DIR}/output"

if [[ -d "${OCP_DIR}/cache" && -d "${OCP_DIR}/temp" ]]; then
    sudo rm -rf "${OCP_DIR}/cache"
    sudo rm -rf "${OCP_DIR}/temp"
    sudo podman rmi -f "${APPLIANCE_IMAGE}" || true
fi

if [[ -d "${OCP_DIR}/iso_builder" ]]; then
    sudo rm -rf "${OCP_DIR}/iso_builder"

    AGENT_ISO_BUILDER_IMAGE=$(getAgentISOBuilderImage)
    sudo podman rmi -f "${AGENT_ISO_BUILDER_IMAGE}" || true
fi

if [[ -d ${BOOT_SERVER_DIR} ]]; then
   sudo pkill agentpxeserver || true
   rm -rf "${BOOT_SERVER_DIR}"
fi

sudo podman rm -f extlb || true
sudo rm "${WORKING_DIR}"/haproxy.* || true
sudo firewall-cmd --zone libvirt --remove-port=${MACHINE_CONFIG_SERVER_PORT}/tcp
sudo firewall-cmd --zone libvirt --remove-port=${KUBE_API_PORT}/tcp
sudo firewall-cmd --zone libvirt --remove-port=${INGRESS_ROUTER_PORT}/tcp

if [[ $NUM_MASTERS == 1 ]] && [[ $IP_STACK == "v4" || $IP_STACK == "v6" ]]; then
    sudo sed -i "/${AGENT_NODE0_IPSV6} console-openshift-console.apps.${CLUSTER_DOMAIN}/d" /etc/hosts
    sudo sed -i "/${AGENT_NODE0_IPSV6} oauth-openshift.apps.${CLUSTER_DOMAIN}/d" /etc/hosts
    sudo sed -i "/${AGENT_NODE0_IPSV6} thanos-querier-openshift-monitoring.apps.${CLUSTER_DOMAIN}/d" /etc/hosts
fi

# Remove anything left behind by an ISCSI run. This deliberately does not depend on the
# current AGENT_E2E_TEST_BOOT_MODE. Cleaning up after the config has been switched to
# another mode would otherwise leave the iscsi network, the targets and the backing files
# in place, and the next ISCSI run would be built on top of them.
if sudo virsh net-list --all | grep -q "${ISCSI_NETWORK}"; then
    sudo virsh net-destroy "${ISCSI_NETWORK}" || true
    sudo virsh net-undefine "${ISCSI_NETWORK}" || true
fi

# clearconfig is all or nothing, so only run it when the targets are ours. That leaves a
# host which is also used for unrelated iscsi work alone. saveconfig persists the cleared
# configuration, otherwise targetcli restores the stale targets on the next host reboot.
if [[ -x "$(command -v targetcli)" ]] && \
   sudo targetcli /iscsi ls 2>/dev/null | grep -q "${ISCSI_INITIATOR_BASE}"; then
    sudo targetcli clearconfig confirm=True
    sudo targetcli / saveconfig
fi

# Globbed rather than derived from NUM_MASTERS/NUM_WORKERS, which describe the current
# config and not necessarily the run that created these files.
sudo rm -f "${SCRIPTDIR}"/iscsi-master-* "${SCRIPTDIR}"/iscsi-worker-*

if [[ -d "$(sudo buildah info --format '{{.store.GraphRoot}}')/vfs" ]] ; then
    sudo buildah rmi -f --storage-driver vfs localhost/appliance-test >/dev/null 2>&1 || true
fi

