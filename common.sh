#!/bin/bash

export RHCOS_IMAGE_VERSION="${RHCOS_IMAGE_VERSION:-47.278}"
export RHCOS_IMAGE_NAME="redhat-coreos-maipo-${RHCOS_IMAGE_VERSION}"
export RHCOS_IMAGE_FILENAME="${RHCOS_IMAGE_NAME}-openstack.qcow2"
