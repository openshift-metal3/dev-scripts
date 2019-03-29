#!/bin/bash

set -ex

source common.sh

# Get the various images
source get_images.sh

# ironic dnsmasq and ipxe config
cp ironic/dnsmasq.conf $IRONIC_DATA_DIR/
cp ironic/dualboot.ipxe ironic/inspector.ipxe $IRONIC_DATA_DIR/html/

# tftpboot must be in the same partition as html when mounted in the
# Ironic containers to avoid "Invalid cross-device link" errors
if [ ! -d $IRONIC_DATA_DIR/tftpboot ] ; then
   mkdir $IRONIC_DATA_DIR/tftpboot
fi

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
    sudo sed --follow-symlinks -i -e 's/ip=eth0:dhcp/ip=eth0:dhcp ip=eth1:dhcp/g' /tmp/mnt/grub2/grub.cfg
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

for name in ironic ironic-inspector dnsmasq httpd; do 
    sudo podman ps | grep -w "$name$" && sudo podman kill $name
    sudo podman ps --all | grep -w "$name$" && sudo podman rm $name -f
done

# Remove existing pod
if  sudo podman pod exists ironic-pod ; then 
    sudo podman pod rm ironic-pod -f
fi

# Create pod
sudo podman pod create -n ironic-pod 

# Start dnsmasq, http, and dnsmasq containers using same image
sudo podman run -d --net host --privileged --name dnsmasq  --pod ironic-pod \
     -v $IRONIC_DATA_DIR:/shared --entrypoint /bin/rundnsmasq ${IRONIC_IMAGE} 

sudo podman run -d --net host --privileged --name httpd --pod ironic-pod \
     -v $IRONIC_DATA_DIR:/shared --entrypoint /bin/runhttpd ${IRONIC_IMAGE} 

sudo podman run -d --net host --privileged --name ironic --pod ironic-pod \
     -v $IRONIC_DATA_DIR:/shared ${IRONIC_IMAGE} 

# Start Ironic Inspector 
sudo podman run -d --net host --privileged --name ironic-inspector --pod ironic-pod "${IRONIC_INSPECTOR_IMAGE}"
