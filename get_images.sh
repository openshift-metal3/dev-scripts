#!/usr/bin/env bash
set -xe

source common.sh

if [ ! -f "$RHCOS_IMAGE_FILENAME" ]; then
    curl --insecure --compressed -L -o "${RHCOS_IMAGE_FILENAME}" "${RHCOS_IMAGE_URL}/${RHCOS_IMAGE_VERSION}/${RHCOS_IMAGE_FILENAME}".gz
fi

mkdir -p images
pushd images

if [ ! -f "${RHCOS_IMAGE_FILENAME_OPENSTACK}" ]; then
    curl --insecure --compressed -L -o "${RHCOS_IMAGE_FILENAME_OPENSTACK}" "${RHCOS_IMAGE_URL}/${RHCOS_IMAGE_VERSION}/${RHCOS_IMAGE_FILENAME_OPENSTACK}".gz
fi

if [ ! -f ironic-python-agent.initramfs ]; then
    curl --insecure --compressed -L https://images.rdoproject.org/master/rdo_trunk/current-tripleo/ironic-python-agent.tar | tar -xf -
fi

popd
