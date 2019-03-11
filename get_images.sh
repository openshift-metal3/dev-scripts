#!/usr/bin/env bash
set -xe

source common.sh

if [ ! -f "$RHCOS_IMAGE_FILENAME" ]; then
    curl --insecure --compressed -L -o "${RHCOS_IMAGE_FILENAME}" "${RHCOS_IMAGE_URL}/${RHCOS_IMAGE_VERSION}/${RHCOS_IMAGE_FILENAME}".gz
fi

mkdir -p "$IRONIC_DATA_DIR/html/images"
# Move images from the old directory to the new one if we have already downloaded them
# TODO: delete this in a week or so
if [ -d images ] ; then
    find images -type f -exec mv {} "$IRONIC_DATA_DIR/html/images/" \;
    rmdir images
fi

pushd "$IRONIC_DATA_DIR/html/images"
if [ ! -f "${RHCOS_IMAGE_FILENAME_OPENSTACK}" ]; then
    curl --insecure --compressed -L -o "${RHCOS_IMAGE_FILENAME_OPENSTACK}" "${RHCOS_IMAGE_URL}/${RHCOS_IMAGE_VERSION}/${RHCOS_IMAGE_FILENAME_OPENSTACK}".gz
fi

if [ ! -f ironic-python-agent.initramfs ]; then
#    curl --insecure --compressed -L https://images.rdoproject.org/master/rdo_trunk/current-tripleo/ironic-python-agent.tar | tar -xf -
    curl --insecure --compressed -L https://images.rdoproject.org/master/rdo_trunk/54c5a6de8ce5b9cfae83632a7d81000721d56071_786d88d2/ironic-python-agent.tar | tar -xf -
fi

popd
