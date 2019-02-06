#!/usr/bin/env bash
set -xe

source common.sh

if [ ! -f "$RHCOS_IMAGE_FILENAME" ]; then
    curl --insecure --compressed -L -o "${RHCOS_IMAGE_FILENAME}" "${RHCOS_IMAGE_URL}/${RHCOS_IMAGE_VERSION}/${RHCOS_IMAGE_FILENAME}".gz
fi

if [ ! -f "${RHCOS_IMAGE_FILENAME_OPENSTACK}" ]; then
    curl --insecure --compressed -L -o "${RHCOS_IMAGE_FILENAME_OPENSTACK}" "${RHCOS_IMAGE_URL}/${RHCOS_IMAGE_VERSION}/${RHCOS_IMAGE_FILENAME_OPENSTACK}".gz
fi
