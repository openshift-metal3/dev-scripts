#!/bin/bash

set -ex

source common.sh

# Get the various images
source get_images.sh

# ironic dnsmasq and ipxe config
cp ironic/dnsmasq.conf $IRONIC_DATA_DIR/
cp ironic/dualboot.ipxe ironic/inspector.ipxe $IRONIC_DATA_DIR/html/

# Now that we have the Environment and the image, we can pull the image and start the ironic service
sudo podman pull "$IRONIC_IMAGE"
sudo podman pull "$IRONIC_INSPECTOR_IMAGE"

# Adding an IP address in the libvirt definition for this network results in
# dnsmasq being run, we don't want that as we have our own dnsmasq, so set
# the IP address here
if [ ! -e /etc/sysconfig/network-scripts/ifcfg-brovc ] ; then
    echo -e "DEVICE=brovc\nONBOOT=yes\nNM_CONTROLLED=no\nTYPE=Ethernet\nBOOTPROTO=static\nIPADDR=172.22.0.1\nNETMASK=255.255.255.0" | sudo dd of=/etc/sysconfig/network-scripts/ifcfg-brovc
    sudo ifdown brovc || true
    sudo ifup brovc
fi

# Workaround so that the dracut network module does dhcp on eth0 & eth1
if [ ! -e $IRONIC_DATA_DIR/html/images/redhat-coreos-maipo-47.284-openstack_dualdhcp.qcow2 ] ; then
    pushd $IRONIC_DATA_DIR/html/images
    qemu-img convert redhat-coreos-maipo-47.284-openstack.qcow2 redhat-coreos-maipo-47.284-openstack.raw
    LOOPBACK=$(sudo losetup --show -f redhat-coreos-maipo-47.284-openstack.raw | cut -f 3 -d /)
    mkdir -p /tmp/mnt
    sudo kpartx -a /dev/$LOOPBACK
    sudo mount /dev/mapper/${LOOPBACK}p1 /tmp/mnt
    sudo sed -i -e 's/ip=eth0:dhcp/ip=eth0:dhcp ip=eth1:dhcp/g' /tmp/mnt/grub2/grub.cfg 
    sudo umount /tmp/mnt
    sudo kpartx -d /dev/${LOOPBACK}
    sudo losetup -d /dev/${LOOPBACK}
    qemu-img convert -O qcow2 -c redhat-coreos-maipo-47.284-openstack.raw redhat-coreos-maipo-47.284-openstack_dualdhcp.qcow2
    rm redhat-coreos-maipo-47.284-openstack.raw
    popd
fi


for name in ironic ironic-inspector ; do 
    sudo podman ps | grep -w "$name$" && sudo podman kill $name
    sudo podman ps --all | grep -w "$name$" && sudo podman rm $name
done

# Start Ironic and inspector
sudo podman run -d --net host --privileged --name ironic \
    -v $IRONIC_DATA_DIR/dnsmasq.conf:/etc/dnsmasq.conf \
    -v $IRONIC_DATA_DIR/html/images:/var/www/html/images \
    -v $IRONIC_DATA_DIR/html/dualboot.ipxe:/var/www/html/dualboot.ipxe \
    -v $IRONIC_DATA_DIR/html/inspector.ipxe:/var/www/html/inspector.ipxe ${IRONIC_IMAGE}
sudo podman run -d --net host --privileged --name ironic-inspector "${IRONIC_INSPECTOR_IMAGE}"
