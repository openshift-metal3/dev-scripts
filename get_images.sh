#!/usr/bin/env bash
set -xe

source common.sh

mkdir -p "$IRONIC_DATA_DIR/html/images"
pushd "$IRONIC_DATA_DIR/html/images"
if [ ! -f "${RHCOS_IMAGE_FILENAME_OPENSTACK}" ]; then
    curl --insecure --compressed -L -o "${RHCOS_IMAGE_FILENAME_OPENSTACK}" "${RHCOS_IMAGE_URL}/${RHCOS_IMAGE_FILENAME_OPENSTACK}"
fi

initramfs="ironic-python-agent.initramfs"
initramfs_min_date=$(date -d "June 4, 2019" +%s)
initramfs_date=0
if [ -f $initramfs ]; then
  initramfs_date=$(date +%s -r ironic-python-agent.initramfs)
fi

if [ ! -f $initramfs ] || [ $initramfs_date -lt $initramfs_min_date ]; then
    curl --insecure --compressed -L https://images.rdoproject.org/master/rdo_trunk/current-tripleo-rdo/ironic-python-agent.tar | tar --overwrite -xf -
fi

popd
