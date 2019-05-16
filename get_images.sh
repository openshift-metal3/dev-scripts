#!/usr/bin/env bash
set -xe

source common.sh

mkdir -p "$IRONIC_DATA_DIR/html/images"
pushd "$IRONIC_DATA_DIR/html/images"
if [ ! -f "${RHCOS_IMAGE_FILENAME_OPENSTACK}" ]; then
    curl --insecure --compressed --connect-timeout 120 -L -o "${RHCOS_IMAGE_FILENAME_OPENSTACK}" "${RHCOS_IMAGE_URL}/${RHCOS_IMAGE_FILENAME_OPENSTACK}"
fi

if [ ! -f ironic-python-agent.initramfs ]; then
    curl --insecure --compressed --connect-timeout 120 -L https://images.rdoproject.org/master/rdo_trunk/current-tripleo-rdo/ironic-python-agent.tar | tar -xf -
fi

popd
