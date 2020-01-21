#!/bin/bash

# Get a valid pull secret (json string) from
# You can get this secret from https://cloud.openshift.com/clusters/install#pull-secret
export PULL_SECRET=$(cat ~/pull-secret.json)

export WORKING_DIR="$HOME"
# Local checkout with https://github.com/metal3-io/metal3-dev-env/pull/160 applied
export METAL3_DEV_ENV="$WORKING_DIR/metal3-dev-env"
export MIRROR_IMAGES=true
export OPENSHIFT_RELEASE_IMAGE="registry.svc.ci.openshift.org/ipv6/release:4.3.0-0.nightly-2020-01-16-123848-ipv6.5"
export EXTERNAL_SUBNET="fd2e:6f44:5dd8:c956::/120"
export DNS_VIP="fd2e:6f44:5dd8:c956:0:0:0:2"
export NETWORK_TYPE="OVNKubernetes"
export CLUSTER_SUBNET="fd01::/48"
export CLUSTER_HOST_PREFIX="64"
export SERVICE_SUBNET="fd02::/112"

# Modify downloaded rhcos images to work around:
# https://bugzilla.redhat.com/show_bug.cgi?id=1787620
#
# cd $WORKING_DIR/ironic/html/images
# gunzip rhcos-43.81.201912131630.0-qemu.x86_64.qcow2.gz
# virt-edit -a rhcos-43.81.201912131630.0-qemu.x86_64.qcow2 -m /dev/sda1 -e "s/ip=any/ip=ens3:dhcp6/g" /grub2/grub.cfg 
# sha256sum rhcos-43.81.201912131630.0-qemu.x86_64.qcow2
# gzip rhcos-43.81.201912131630.0-qemu.x86_64.qcow2
# sha256sum rhcos-43.81.201912131630.0-qemu.x86_64.qcow2.gz
# update .sha256sum file

export MACHINE_OS_BOOTSTRAP_IMAGE_UNCOMPRESSED_SHA256="21e424f6ebfef68171d38088caeb1365d3b11e3d9f492304a3b7d6704c2b59fa"
export MACHINE_OS_BOOTSTRAP_IMAGE_SHA256="307ed6f8675fcc5b5f62f4711ebc55b54bdfb9175decff357241f3fb979d564c"
#export MACHINE_OS_IMAGE_UNCOMPRESSED_SHA256="d41814d65f300222dde0cf3c59a04c37b459cb3f4fb696da02832af212cdc8d3"
#export MACHINE_OS_IMAGE_SHA256="6c7016ec68d46c07937949644d6bbc74d4f55ebdb83872bce77f47ce2ee6d671"
