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
sudo cp ocp/bootstrap.ign /var/lib/libvirt/images/${CLUSTER_NAME}-bootstrap.ign
./get_rhcos_image.sh
LATEST_IMAGE=$(ls -ltr redhat-coreos-maipo-*.qcow2 | tail -n1 | awk '{print $9}')
sudo cp $LATEST_IMAGE /var/lib/libvirt/images/${CLUSTER_NAME}-bootstrap.qcow2
cp bootstrap-config/bootstrap-vm.xml ocp
cp bootstrap-config/bootstrap-net.xml ocp
cp bootstrap-config/bootstrap-vol-ign.xml ocp
sed -i "s/CLUSTER_NAME/${CLUSTER_NAME}/g" ocp/bootstrap-vm.xml
sed -i "s/CLUSTER_NAME/${CLUSTER_NAME}/g" ocp/bootstrap-net.xml
sed -i "s/CLUSTER_NAME/${CLUSTER_NAME}/g" ocp/bootstrap-vol-ign.xml
sed -i "s/BASE_DOMAIN/${BASE_DOMAIN}/g" ocp/bootstrap-net.xml
sudo virsh net-create ocp/bootstrap-net.xml
sudo virsh create ocp/bootstrap-vm.xml
