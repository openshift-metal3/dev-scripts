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
if [ ! -e /etc/sysconfig/network-scripts/ifcfg-provisioning ] ; then
    echo -e "DEVICE=provisioning\nONBOOT=yes\nNM_CONTROLLED=no\nTYPE=Ethernet\nBOOTPROTO=static\nIPADDR=172.22.0.1\nNETMASK=255.255.255.0" | sudo dd of=/etc/sysconfig/network-scripts/ifcfg-provisioning
fi
sudo ifdown provisioning || true
sudo ifup provisioning

# Add firewall rules to ensure the IPA ramdisk can reach Ironic and Inspector APIs on the host
for port in 5050 6385 ; do
    if ! sudo iptables -C INPUT -i provisioning -p tcp -m tcp --dport $port -j ACCEPT > /dev/null 2>&1; then
        sudo iptables -I INPUT -i provisioning -p tcp -m tcp --dport $port -j ACCEPT
    fi
done

pushd $IRONIC_DATA_DIR/html/images

# Workaround so that the dracut network module does dhcp on eth0 & eth1
RHCOS_IMAGE_FILENAME_RAW="${RHCOS_IMAGE_FILENAME_OPENSTACK}.raw"
if [ ! -e "$RHCOS_IMAGE_FILENAME_DUALDHCP" ] ; then
    # Calculate the disksize required for the partitions on the image
    # we do this to reduce the disk size so that ironic doesn't have to write as
    # much data during deploy, as the default upstream disk image is way bigger
    # then it needs to be. Were are adding the partition sizes and multiplying by 1.2.
    DISKSIZE=$(virt-filesystems -a "$RHCOS_IMAGE_FILENAME_OPENSTACK" -l | grep /dev/ | awk '{s+=$5} END {print s*1.2}')
    truncate --size $DISKSIZE "${RHCOS_IMAGE_FILENAME_RAW}"
    virt-resize --no-extra-partition "${RHCOS_IMAGE_FILENAME_OPENSTACK}" "${RHCOS_IMAGE_FILENAME_RAW}"

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
fi

if [ ! -e "$RHCOS_IMAGE_FILENAME_DUALDHCP.md5sum" -o \
     "$RHCOS_IMAGE_FILENAME_DUALDHCP" -nt "$RHCOS_IMAGE_FILENAME_DUALDHCP.md5sum" ] ; then
    md5sum "$RHCOS_IMAGE_FILENAME_DUALDHCP" | cut -f 1 -d " " > "$RHCOS_IMAGE_FILENAME_DUALDHCP.md5sum"
fi

ln -sf "$RHCOS_IMAGE_FILENAME_DUALDHCP" "$RHCOS_IMAGE_FILENAME_LATEST"
ln -sf "$RHCOS_IMAGE_FILENAME_DUALDHCP.md5sum" "$RHCOS_IMAGE_FILENAME_LATEST.md5sum"
popd

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
