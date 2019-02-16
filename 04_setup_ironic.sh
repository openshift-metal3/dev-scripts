#!/bin/bash

set -ex

source common.sh

# Get the various images
source get_images.sh

# ironic dnsmasq and ipxe config
cp ironic/dnsmasq.conf $IRONIC_DATA_DIR/
cp ironic/dualboot.ipxe ironic/inspector.ipxe $IRONIC_DATA_DIR/html/

# Either pull or build the ironic images
# To build the IRONIC image set
# IRONIC_IMAGE=https://github.com/metalkube/metalkube-ironic
for IMAGE_VAR in IRONIC_IMAGE IRONIC_INSPECTOR_IMAGE ; do
    IMAGE=${!IMAGE_VAR}
    # Is it a git repo?
    if [[ "$IMAGE" =~ "://" ]] ; then
        REPOPATH=~/${IMAGE##*/}
        # Clone to ~ if not there already
        [ -e "$REPOPATH" ] || git clone $IMAGE $REPOPATH
        cd $REPOPATH
        export $IMAGE_VAR=localhost/${IMAGE##*/}:latest
        sudo podman build -t ${!IMAGE_VAR} .
        cd -
    else
        sudo podman pull "$IMAGE"
    fi
done

# Adding an IP address in the libvirt definition for this network results in
# dnsmasq being run, we don't want that as we have our own dnsmasq, so set
# the IP address here
if [ ! -e /etc/sysconfig/network-scripts/ifcfg-brovc ] ; then
    echo -e "DEVICE=brovc\nONBOOT=yes\nNM_CONTROLLED=no\nTYPE=Ethernet\nBOOTPROTO=static\nIPADDR=172.22.0.1\nNETMASK=255.255.255.0" | sudo dd of=/etc/sysconfig/network-scripts/ifcfg-brovc
    sudo ifdown brovc || true
    sudo ifup brovc
fi

# Workaround so that the dracut network module does dhcp on eth0 & eth1
RHCOS_IMAGE_FILENAME_RAW="${RHCOS_IMAGE_FILENAME_OPENSTACK}.raw"
if [ ! -e "$IRONIC_DATA_DIR/html/images/$RHCOS_IMAGE_FILENAME_DUALDHCP" ] ; then
    pushd $IRONIC_DATA_DIR/html/images
    qemu-img convert "$RHCOS_IMAGE_FILENAME_OPENSTACK" "${RHCOS_IMAGE_FILENAME_RAW}"
    LOOPBACK=$(sudo losetup --show -f "${RHCOS_IMAGE_FILENAME_RAW}" | cut -f 3 -d /)
    mkdir -p /tmp/mnt
    sudo kpartx -a /dev/$LOOPBACK
    sudo mount /dev/mapper/${LOOPBACK}p1 /tmp/mnt
    sudo sed -i -e 's/ip=eth0:dhcp/ip=eth0:dhcp ip=eth1:dhcp/g' /tmp/mnt/grub2/grub.cfg 
    sudo umount /tmp/mnt
    sudo kpartx -d /dev/${LOOPBACK}
    sudo losetup -d /dev/${LOOPBACK}
    qemu-img convert -O qcow2 -c "$RHCOS_IMAGE_FILENAME_RAW" "$RHCOS_IMAGE_FILENAME_DUALDHCP"
    rm "$RHCOS_IMAGE_FILENAME_RAW"
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
