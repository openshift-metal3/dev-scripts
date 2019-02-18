#!/usr/bin/env bash
set -x
set -e

source ocp_install_env.sh
source common.sh
source get_images.sh
source utils.sh

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

# Apply patches to bootstrap ignition
apply_ignition_patches bootstrap "$IGN_FILE"

LATEST_IMAGE=$(ls -ltr redhat-coreos-maipo-*-qemu.qcow2 | tail -n1 | awk '{print $9}')
sudo cp $LATEST_IMAGE /var/lib/libvirt/images/${CLUSTER_NAME}-bootstrap.qcow2
sudo qemu-img resize /var/lib/libvirt/images/${CLUSTER_NAME}-bootstrap.qcow2 50G
sudo virt-install --connect qemu:///system \
             --import \
             --name ${CLUSTER_NAME}-bootstrap \
             --ram 4096 --vcpus 4 \
             --os-type=linux \
             --os-variant=virtio26 \
             --disk path=/var/lib/libvirt/images/${CLUSTER_NAME}-bootstrap.qcow2,format=qcow2,bus=virtio \
             --vnc --noautoconsole \
             --network bridge=baremetal --network bridge=brovc \
             --print-xml > ocp/bootstrap-vm.xml
sed -i 's|type="kvm"|type="kvm" xmlns:qemu="http://libvirt.org/schemas/domain/qemu/1.0"|' ocp/bootstrap-vm.xml
sed -i "/<\/devices>/a <qemu:commandline>\n  <qemu:arg value='-fw_cfg'/>\n  <qemu:arg value='name=opt/com.coreos/config,file=${IGN_FILE}'/>\n</qemu:commandline>" ocp/bootstrap-vm.xml
sudo virsh define ocp/bootstrap-vm.xml
sudo virsh start ${CLUSTER_NAME}-bootstrap
sleep 10

while ! domain_net_ip ${CLUSTER_NAME}-bootstrap baremetal; do
  echo "Waiting for ${CLUSTER_NAME}-bootstrap interface to become active.."
  sleep 10
done

# NOTE: This is equivalent to the external API DNS record pointing the API to the API VIP
IP=$(domain_net_ip ${CLUSTER_NAME}-bootstrap baremetal)
API_IP=$(dig +noall +answer "api.${CLUSTER_DOMAIN}" @$(network_ip baremetal) | awk '{print $NF}')
echo "address=/api.${CLUSTER_DOMAIN}/${API_IP}" | sudo tee /etc/NetworkManager/dnsmasq.d/openshift.conf
sudo systemctl reload NetworkManager

# Wait for ssh to start
while ! ssh -o "StrictHostKeyChecking=no" core@$IP id ; do sleep 5 ; done

# ironic dnsmasq and ipxe config
cat ironic/dnsmasq.conf | ssh -o "StrictHostKeyChecking=no" core@$IP sudo dd of=dnsmasq.conf
cat ironic/dualboot.ipxe | ssh -o "StrictHostKeyChecking=no" core@$IP sudo dd of=dualboot.ipxe
cat ironic/inspector.ipxe | ssh -o "StrictHostKeyChecking=no" core@$IP sudo dd of=inspector.ipxe

# Workaround so that the dracut network module does dhcp on eth0 & eth1
if [ ! -e images/redhat-coreos-maipo-47.284-openstack_dualdhcp.qcow2 ] ; then
    qemu-img convert images/redhat-coreos-maipo-47.284-openstack.qcow2 images/redhat-coreos-maipo-47.284-openstack.raw
    LOOPBACK=$(sudo losetup --show -f images/redhat-coreos-maipo-47.284-openstack.raw | cut -f 3 -d /)
    mkdir -p /tmp/mnt
    sudo kpartx -a /dev/$LOOPBACK
    sudo mount /dev/mapper/${LOOPBACK}p1 /tmp/mnt
    sudo sed -i -e 's/ip=eth0:dhcp/ip=eth0:dhcp ip=eth1:dhcp/g' /tmp/mnt/grub2/grub.cfg
    sudo umount /tmp/mnt
    sudo kpartx -d /dev/${LOOPBACK}
    sudo losetup -d /dev/${LOOPBACK}
    qemu-img convert -O qcow2 -c images/redhat-coreos-maipo-47.284-openstack.raw images/redhat-coreos-maipo-47.284-openstack_dualdhcp.qcow2
    rm images/redhat-coreos-maipo-47.284-openstack.raw
fi

# Copy images the bootstrap node
tar -cf - images | ssh -o "StrictHostKeyChecking=no" "core@$IP" tar -xf -

# Retrieve and start the ironic container
IRONIC_IMAGE=${IRONIC_IMAGE:-"quay.io/metalkube/metalkube-ironic"}
echo -e "RHCOS_IMAGE_FILENAME_OPENSTACK=${RHCOS_IMAGE_FILENAME_OPENSTACK}\nIRONIC_IMAGE=${IRONIC_IMAGE}" \
    | ssh -o "StrictHostKeyChecking=no" core@$IP sudo dd of=/etc/ironicservice

# Now that we have the Environment and the image, we can pull the image and start the ironic service
ssh -o "StrictHostKeyChecking=no" core@$IP sudo podman pull "$IRONIC_IMAGE"
ssh -o "StrictHostKeyChecking=no" core@$IP sudo systemctl start ironic.service

# Retrieve and start the inspector container
IRONIC_INSPECTOR_IMAGE=${IRONIC_INSPECTOR_IMAGE:-"quay.io/metalkube/metalkube-ironic-inspector"}
ssh -o "StrictHostKeyChecking=no" "core@$IP" sudo podman pull "${IRONIC_INSPECTOR_IMAGE}"

ssh -o "StrictHostKeyChecking=no" core@$IP sudo podman run \
    -d --net host --privileged --name ironic-inspector \
    "${IRONIC_INSPECTOR_IMAGE}"

# Create a master_nodes.json file
jq '.nodes[0:3] | {nodes: .}' "${NODES_FILE}" | tee ocp/master_nodes.json

MASTER_INTERFACE="eth1"

# Fix etcd discovery on bootstrap
rm -rf ocp/machineconfigs
mkdir -p ocp/machineconfigs/temp
# Find master machine config name
while [ -z $(ssh -o StrictHostKeyChecking=no "core@$IP" sudo ls /etc/mcs/bootstrap/machine-configs/master*) ]; do sleep 5; done

MASTER_CONFIG=$(ssh -o StrictHostKeyChecking=no "core@$IP" sudo ls /etc/mcs/bootstrap/machine-configs/master*)
ssh -o "StrictHostKeyChecking=no" "core@$IP" sudo cat "${MASTER_CONFIG}" > ocp/machineconfigs/temp/master.yaml
# Extract etcd-member.yaml part
yq -r ".spec.config.storage.files[] | select(.path==\"/etc/kubernetes/manifests/etcd-member.yaml\") | .contents.source" ocp/machineconfigs/temp/master.yaml | sed 's;data:,;;' > ocp/machineconfigs/temp/etcd-member.urlencode
# URL decode
cat ocp/machineconfigs/temp/etcd-member.urlencode | urldecode > ocp/machineconfigs/etcd-member.yaml
# Add a new param to args in discovery container
sed -i "s;- \"run\";- \"run\"\\n    - \"--if-name=${MASTER_INTERFACE}\";g" ocp/machineconfigs/etcd-member.yaml
# URL encode yaml
cat ocp/machineconfigs/etcd-member.yaml | jq -sRr @uri > ocp/machineconfigs/temp/etcd-member.urlencode_updated
# Replace etcd-member contents in the yaml
sed "s;$(cat ocp/machineconfigs/temp/etcd-member.urlencode);$(cat ocp/machineconfigs/temp/etcd-member.urlencode_updated);g" ocp/machineconfigs/temp/master.yaml > ocp/machineconfigs/master.yaml
# Copy the changed file back to bootstrap
cat ocp/machineconfigs/master.yaml | ssh -o "StrictHostKeyChecking=no" "core@$IP" sudo dd of="${MASTER_CONFIG}"

echo "You can now ssh to \"$IP\" as the core user"
