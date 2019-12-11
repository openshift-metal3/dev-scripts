#!/usr/bin/env bash
set -xe

source logging.sh
source common.sh
source utils.sh
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
    -b -vvv ${VM_SETUP_PATH}/setup-playbook.yml

if [ "${RHEL8}" = "True" ] ; then
    ZONE="\nZONE=libvirt"
fi

if [ "$MANAGE_INT_BRIDGE" == "y" ]; then
    # Create the baremetal bridge
    if [ ! -e /etc/sysconfig/network-scripts/ifcfg-baremetal2 ] ; then
        echo -e "DEVICE=baremetal2\nTYPE=Bridge\nONBOOT=yes\nNM_CONTROLLED=no${ZONE}" | sudo dd of=/etc/sysconfig/network-scripts/ifcfg-baremetal2
    fi
    sudo ifdown baremetal2 || true
    sudo ifup baremetal2
fi

# restart the libvirt network so it applies an ip to the bridge
if [ "$MANAGE_BR_BRIDGE" == "y" ] ; then
    sudo virsh net-destroy baremetal2
    sudo virsh net-start baremetal2
fi

# Add firewall rules to ensure the image caches can be reached on the host
for PORT in 80 5000 ; do
    if [ "${RHEL8}" = "True" ] ; then
        sudo firewall-cmd --zone=libvirt --add-port=$PORT/tcp
        sudo firewall-cmd --zone=libvirt --add-port=$PORT/tcp --permanent
    else
        if ! sudo iptables -C INPUT -i baremetal2 -p tcp -m tcp --dport $PORT -j ACCEPT > /dev/null 2>&1; then
            sudo iptables -I INPUT -i baremetal2 -p tcp -m tcp --dport $PORT -j ACCEPT
        fi
    fi
done

# Allow ipmi to the virtual bmc processes that we just started
VBMC_MAX_PORT=$((6230 + ${NUM_MASTERS} + ${NUM_MASTERS2} + ${NUM_WORKERS} + ${NUM_WORKERS2} - 1))
if [ "${RHEL8}" = "True" ] ; then
    sudo firewall-cmd --zone=libvirt --add-port=6230-${VBMC_MAX_PORT}/udp
    sudo firewall-cmd --zone=libvirt --add-port=6230-${VBMC_MAX_PORT}/udp --permanent
else
    if ! sudo iptables -C INPUT -i baremetal2 -p udp -m udp --dport 6230:${VBMC_MAX_PORT} -j ACCEPT 2>/dev/null ; then
        sudo iptables -I INPUT -i baremetal2 -p udp -m udp --dport 6230:${VBMC_MAX_PORT} -j ACCEPT
    fi
fi
