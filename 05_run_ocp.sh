#!/usr/bin/env bash
set -x
set -e

source ocp_install_env.sh
source common.sh

# FIXME this is configuring for the libvirt backend which is dev-only ref
# https://github.com/openshift/installer/blob/master/docs/dev/libvirt-howto.md
# We may need some additional steps from that doc in 02* and also to make the
# qemu endpoint configurable?
if [ ! -d ocp ]; then
    mkdir -p ocp
    export CLUSTER_ID=$(uuidgen --random)
    cat > ocp/install-config.yaml << EOF
apiVersion: v1beta1
baseDomain: ${BASE_DOMAIN}
clusterID:  ${CLUSTER_ID}
machines:
- name:     master
  platform: {}
  replicas: null
- name:     worker
  platform: {}
  replicas: null
metadata:
  creationTimestamp: null
  name: ${CLUSTER_NAME}
networking:
  clusterNetworks:
  - cidr: 10.128.0.0/14
    hostSubnetLength: 9
  machineCIDR: 192.168.126.0/24
  serviceCIDR: 172.30.0.0/16
  type: OpenshiftSDN
platform:
  libvirt:
    URI: qemu:///system
    network:
      if: tt0
pullSecret: |
  ${PULL_SECRET}
sshKey: |
  ${SSH_PUB_KEY}
EOF
fi


$GOPATH/src/github.com/openshift/installer/bin/openshift-install --dir ocp --log-level=debug create ignition-configs

# Here we can make any necessary changes to the ignition configs/manifests
# they can later be sync'd back into the installer via a new baremetal target

# Now re create the cluster (using the existing install-config and ignition-configs)
# Since we set the replicas to null, we should only get the bootstrap VM
# FIXME(shardy) this doesn't work, it creates the bootstrap and one master
#$GOPATH/src/github.com/openshift/installer/bin/openshift-install --dir ocp --log-level=debug create cluster
#exit 1

# ... so for now lets create the bootstrap VM manually and use the generated ignition config
# See https://coreos.com/os/docs/latest/booting-with-libvirt.html
IGN_FILE="/var/lib/libvirt/images/${CLUSTER_NAME}-bootstrap.ign"
sudo cp ocp/bootstrap.ign ${IGN_FILE}
./get_rhcos_image.sh
LATEST_IMAGE=$(ls -ltr redhat-coreos-maipo-*-qemu.qcow2 | tail -n1 | awk '{print $9}')
sudo cp $LATEST_IMAGE /var/lib/libvirt/images/${CLUSTER_NAME}-bootstrap.qcow2
virt-install --connect qemu:///system \
             --import \
             --name ${CLUSTER_NAME}-bootstrap \
             --ram 4096 --vcpus 4 \
             --os-type=linux \
             --os-variant=virtio26 \
             --disk path=/var/lib/libvirt/images/${CLUSTER_NAME}-bootstrap.qcow2,format=qcow2,bus=virtio \
             --vnc --noautoconsole \
             --print-xml > ocp/bootstrap-vm.xml
sed -i 's|type="kvm"|type="kvm" xmlns:qemu="http://libvirt.org/schemas/domain/qemu/1.0"|' ocp/bootstrap-vm.xml
sed -i "/<\/devices>/a <qemu:commandline>\n  <qemu:arg value='-fw_cfg'/>\n  <qemu:arg value='name=opt/com.coreos/config,file=${IGN_FILE}'/>\n</qemu:commandline>" ocp/bootstrap-vm.xml
sudo virsh define ocp/bootstrap-vm.xml
sudo virsh start ${CLUSTER_NAME}-bootstrap
sleep 10
VM_MAC=$(sudo virsh dumpxml ${CLUSTER_NAME}-bootstrap | grep "mac address" | cut -d\' -f2)
while ! sudo virsh domifaddr ${CLUSTER_NAME}-bootstrap | grep -q ${VM_MAC}; do
  echo "Waiting for ${CLUSTER_NAME}-bootstrap interface to become active.."
  sleep 10
done
sudo virsh domifaddr ${CLUSTER_NAME}-bootstrap
echo "You can now ssh to the IP listed above as the core user"
