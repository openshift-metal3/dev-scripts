#!/bin/bash
set -x

source logging.sh
source common.sh
source ocp_install_env.sh

sudo systemctl stop fix_certs.timer

if [ -d ${OCP_DIR} ]; then
    ${OCP_DIR}/openshift-install --dir ${OCP_DIR} --log-level=debug destroy bootstrap
    ${OCP_DIR}/openshift-install --dir ${OCP_DIR} --log-level=debug destroy cluster
    rm -rf ${OCP_DIR}
fi

sudo rm -rf /etc/NetworkManager/dnsmasq.d/openshift-${CLUSTER_NAME}.conf

# Cleanup ssh keys for baremetal network
if [ -f $HOME/.ssh/known_hosts ]; then
    EXT_SUB_V4=$(echo "${EXTERNAL_SUBNET_V4}" | cut -d"/" -f1 | sed "s/0$//")
    sed -i "/^${EXT_SUB_V4}/d" $HOME/.ssh/known_hosts
    EXT_SUB_V6=$(echo "${EXTERNAL_SUBNET_V6}" | cut -d"/" -f1 | sed "s/0$//")
    sed -i "/^${EXT_SUB_V^}/d" $HOME/.ssh/known_hosts
    PRO_SUB=$(echo "${PROVISIONING_NETWORK}" | cut -d"/" -f1 | sed "s/0$//")
    sed -i "/^${PRO_SUB}/d" $HOME/.ssh/known_hosts
    sed -i "/^api.${CLUSTER_DOMAIN}/d" $HOME/.ssh/known_hosts
fi

if test -f assets/templates/99_master-chronyd-redhat.yaml ; then
    rm -f assets/templates/99_master-chronyd-redhat.yaml
fi
if test -f assets/templates/99_worker-chronyd-redhat.yaml ; then
    rm -f assets/templates/99_worker-chronyd-redhat.yaml
fi

# If the installer fails before terraform completes the destroy bootstrap
# cleanup doesn't clean up the VM/volumes created..
for vm in $(sudo virsh list --all --name | grep "^${CLUSTER_NAME}.*bootstrap"); do
  sudo virsh destroy $vm
  sudo virsh undefine $vm --remove-all-storage
done
# The .ign volume isn't deleted via --remove-all-storage
VOLS="$(sudo virsh vol-list --pool default | awk '{print $1}' | grep "^${CLUSTER_NAME}.*bootstrap")"
for v in $VOLS; do
  sudo virsh vol-delete $v --pool default
done

if [ -d assets/generated ]; then
  rm -rf assets/generated
fi
