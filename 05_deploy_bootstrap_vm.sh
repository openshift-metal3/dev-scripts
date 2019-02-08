#!/usr/bin/env bash
set -x
set -e

source ocp_install_env.sh
source common.sh
source get_rhcos_image.sh
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
             --network default --network bridge=brovc \
             --print-xml > ocp/bootstrap-vm.xml
sed -i 's|type="kvm"|type="kvm" xmlns:qemu="http://libvirt.org/schemas/domain/qemu/1.0"|' ocp/bootstrap-vm.xml
sed -i "/<\/devices>/a <qemu:commandline>\n  <qemu:arg value='-fw_cfg'/>\n  <qemu:arg value='name=opt/com.coreos/config,file=${IGN_FILE}'/>\n</qemu:commandline>" ocp/bootstrap-vm.xml
sudo virsh define ocp/bootstrap-vm.xml
sudo virsh start ${CLUSTER_NAME}-bootstrap
sleep 10
VM_MAC=$(sudo virsh dumpxml ${CLUSTER_NAME}-bootstrap | grep "mac address" | head -n 1 | cut -d\' -f2)
while ! sudo virsh domifaddr ${CLUSTER_NAME}-bootstrap | grep -q ${VM_MAC}; do
  echo "Waiting for ${CLUSTER_NAME}-bootstrap interface to become active.."
  sleep 10
done
sudo virsh domifaddr ${CLUSTER_NAME}-bootstrap

# NOTE: This hardcodes CLUSTER_NAME-api.BASE_DOMAIN to the bootstrap node.
# TODO: Point instead to the DNS VIP when we have that. E.g.: server=/BASE_DOMAIN/DNS_VIP
IP=$(sudo virsh domifaddr ostest-bootstrap | grep 122 | awk '{print $4}' | grep -o '^[^/]*')
echo "addn-hosts=/etc/hosts.openshift" | sudo tee /etc/NetworkManager/dnsmasq.d/openshift.conf
echo "${IP} ${CLUSTER_NAME}-api.${BASE_DOMAIN}" | sudo tee /etc/hosts.openshift
sudo systemctl restart NetworkManager

# Wait for ssh to start
while ! ssh -o "StrictHostKeyChecking=no" core@$IP id ; do sleep 5 ; done

# Using 172.22.0.1 on the provisioning network for PXE and the ironic API
echo -e "DEVICE=eth1\nONBOOT=yes\nTYPE=Ethernet\nBOOTPROTO=static\nIPADDR=172.22.0.1\nNETMASK=255.255.255.0" | ssh -o "StrictHostKeyChecking=no" core@$IP sudo dd of=/etc/sysconfig/network-scripts/ifcfg-eth1
ssh -o "StrictHostKeyChecking=no" core@$IP sudo ifup eth1

# Internal dnsmasq should reserve IP addresses for each master
cp -f ironic/dnsmasq.conf /tmp
for i in 0 1 2; do
  NODE_MAC=$(cat "${WORKING_DIR}/ironic_nodes.json" | jq -r ".nodes[${i}].ports[0].address")
  NODE_IP="172.22.0.2${i}"
  HOSTNAME="${CLUSTER_NAME}-etcd-${i}.${BASE_DOMAIN}"
  # Make sure internal dnsmasq would assign an expected IP
  echo "dhcp-host=${NODE_MAC},${HOSTNAME},${NODE_IP}" >> /tmp/dnsmasq.conf
  # Reconfigure "external" dnsmasq
  echo "${NODE_IP} ${HOSTNAME} ${CLUSTER_NAME}-api.${BASE_DOMAIN}" | sudo tee -a /etc/hosts.openshift
  echo "srv-host=_etcd-server-ssl._tcp.${CLUSTER_NAME}.${BASE_DOMAIN},${HOSTNAME},2380,0,0" | sudo tee -a /etc/NetworkManager/dnsmasq.d/openshift.conf
done
sudo systemctl reload NetworkManager
cat /tmp/dnsmasq.conf | ssh -o "StrictHostKeyChecking=no" core@$IP sudo dd of=dnsmasq.conf

# Build and start the ironic container
cat ironic/runironic.sh | ssh -o "StrictHostKeyChecking=no" core@$IP sudo dd of=runironic.sh
cat ironic/Dockerfile | ssh -o "StrictHostKeyChecking=no" core@$IP sudo dd of=Dockerfile
ssh -o "StrictHostKeyChecking=no" core@$IP sudo podman build \
    --build-arg RHCOS_IMAGE_URL=${RHCOS_IMAGE_URL} \
    --build-arg RHCOS_IMAGE_VERSION=${RHCOS_IMAGE_VERSION} \
    --build-arg RHCOS_IMAGE_FILENAME_OPENSTACK=${RHCOS_IMAGE_FILENAME_OPENSTACK} \
    -t ironic:latest .
ssh -o "StrictHostKeyChecking=no" core@$IP sudo podman run \
    -d --net host --privileged --name ironic localhost/ironic

# Create a master_nodes.json file
jq '.nodes[0:3] | {nodes: .}' "${WORKING_DIR}/ironic_nodes.json" | tee ocp/master_nodes.json

echo "You can now ssh to \"$IP\" as the core user"
