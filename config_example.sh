#!/bin/bash

# You can get this token from https://api.ci.openshift.org/ by
# clicking on your name in the top right corner and coping the login
# command (the token is part of the command)
set +x
export CI_TOKEN=''
set -x

# Select a different release stream from which to pull the latest image, if the
# image name is not specified
#export OPENSHIFT_RELEASE_STREAM=4.7

# Select a different release type from which to pull the latest image,
# e.g ci, nightly or ga
# if using ga then set OPENSHIFT_VERSION to the required version.
#export OPENSHIFT_RELEASE_TYPE=nightly

# Use <NAME>_LOCAL_IMAGE to build or use copy of container images locally e.g.
#export IRONIC_INSPECTOR_LOCAL_IMAGE=https://github.com/metal3-io/ironic-inspector
#export IRONIC_LOCAL_IMAGE=quay.io/username/ironic
#export MACHINE_CONFIG_OPERATOR_LOCAL_IMAGE=https://github.com/openshift/machine-config-operator
# NOTE: If a checkout already exists in $HOME, it won't be re-created.
# NOTE: You must set CUSTOM_REPO_FILE to build some OpenShift images, e.g. ironic ones.

# Set this variable to point the custom base image to a different location
# It can be an absolute path or a local path under the dev-scripts dir
# export BASE_IMAGE_DIR=base-image

# To build custom images based on custom base images with custom repositories
# put all the custom repositories in a .repo file inside the base-image directory
# (default to dev-scripts/base-image) and set this variable with the name of the
# .repo file, e.g. if the filename is ocp46.repo
# export CUSTOM_REPO_FILE=ocp46.repo

# If needed, we can fetch the change associated to a Pull Request for the images
# we're building locally. Specifying the PR number will fetch the PR, switch the
# local image repo to it, and build the image locally with that specific change.
# For example, for the PR #34 for the ironic-image:
# export IRONIC_PR=34

# IP stack version.  The default is "v6".  You may also set "v4".
# For dual stack (IPv4 + IPv6), use "v4v6".
#export IP_STACK=v4

# BMC type. Valid values are redfish, redfish-virtualmedia, or ipmi.
#export BMC_DRIVER=redfish-virtualmedia

# Mirror latest ci images to local registry. This is always true for IPv6, but can be turned off
# for an IPv4 install.
#export MIRROR_IMAGES=true

# Switch to upstream metal3-io ironic images instead of openshift ones.
#export UPSTREAM_IRONIC=true

# SSH key used to ssh into deployed hosts.  This must be the contents of the
# variable, not the filename. The contents of ~/.ssh/id_rsa.pub are used by
# default.
#export SSH_PUB_KEY=$(cat ~/.ssh/id_rsa.pub)

# Configure custom ntp servers if needed
#export NTP_SERVERS="00.my.internal.ntp.server.com;01.other.ntp.server.com"

# Indicate number of workers to deploy
#export NUM_WORKERS=0

# Indicate number of extra VMs to create but not deploy
#export NUM_EXTRA_WORKERS=0

# Provisioning interface on the helper ndoe
#export PRO_IF="eno1"

# Internal interface
#export INT_IF="eno2"

# Provisioning interface within the cluster
#export CLUSTER_PRO_IF="eno1"

# Which disk to deploy
#export ROOT_DISK="/dev/sda"

# Cluster name
#export CLUSTER_NAME="mycluster"

# Domain name
#export BASE_DOMAIN="kni.lab.metal3.io"

# Manage bridge
#export MANAGE_BR_BRIDGE=n

# Path to the json files with ipmi credentials
#export NODES_FILE="/root/git/dev-scripts/bm.json"

# Whether the installation is on baremetal or not
#export NODES_PLATFORM=BM

# DNS_VIP
#export DNS_VIP="11.0.0.2"

# Network type
#export NETWORK_TYPE="OpenShiftSDN"

# Provisioning network
#export PROVISIONING_NETWORK="172.23.0.0/16"

# IPv6 Provisioning network
#export PROVISIONING_NETWORK=fd00:1101::0/64

# Provisioning network profile, can be set to "Managed" or "Disabled"
#PROVISIONING_NETWORK_PROFILE=Managed

# External subnet
#export EXTERNAL_SUBNET_V4="11.0.0.0/24"
#export EXTERNAL_SUBNET_V6="fd2e:6f44:5dd8:c956::/120"

# Cluster Subnet
#export CLUSTER_SUBNET_V4="10.128.0.0/14"
#export CLUSTER_HOST_PREFIX_V4="23"
#export CLUSTER_SUBNET_V6="fd01::/48
#export CLUSTER_HOST_PREFIX_V6="64"

# Cluster Host Prefix

# Service Subnet
#export SERVICE_SUBNET_V4="172.30.0.0/16"
#export SERVICE_SUBNET_V6="fd02::/112"

# Enable testing of custom machine-api-operator-image
#export TEST_CUSTOM_MAO=true

# Custom machine-api-operator image with tag
#export CUSTOM_MAO_IMAGE="quay.io/mao-user/machine-api-operator:mao-fix"

# Git repository that is holding any custom machine-api-operator changes
#export REPO_NAME="mao-user"

# Name of branch in the above repo which contains the custom MAO changes
#export MAO_BRANCH="mao-fix"

#export LOCAL_REGISTRY_DNS_NAME="virthost.ostest.test.metalkube.org"
#export LOCAL_REGISTRY_PORT="5000"

# configure username for registry
#export REGISTRY_USER=some-user

# congiugre password for registry user
#export REGISTRY_PASS=some-pass

# configure base directory for registry
#export REGISTRY_DIR=/opt/registry

# configure location of mirror's creds
#export REGISTRY_CREDS=${REGISTRY_CREDS:-$USER/private-mirror.json}

# Install operator-sdk for local testing of baremetal-operator
#export INSTALL_OPERATOR_SDK=1

# Set a custom hostname format for masters. This is a format string that should
# include one %d field, which will be replaced with the number of the node.
#export MASTER_HOSTNAME_FORMAT=master-%d

# Set a custom hostname format for workers. This is a format string that should
# include one %d field, which will be replaced with the number of the node.
#export WORKER_HOSTNAME_FORMAT=worker-%d

# Change VM resources for masters
#export MASTER_MEMORY=16384
#export MASTER_DISK=20
#export MASTER_VCPU=8

# Change VM resources for workers
#export WORKER_MEMORY=8192
#export WORKER_DISK=20
#export WORKER_VCPU=4

# Provide additional master/worker ignition configuration, will be
# merged with the installer provided config, can be used to modify
# the default nic configuration etc
#export IGNITION_EXTRA=extra.ign

# Folder where to copy extra manifests for the cluster deployment
#export ASSETS_EXTRA_FOLDER=local_file_path

# Enable FIPS mode
#export FIPS_MODE=true

# In order to test using unicast for keepalived, one needs to disable multicast.
# Setting this variable to true will block multicast via ebtables for both IPv4 and IPv6.
#export DISABLE_MULTICAST=false

##
## Multi-cluster/Hive variables
##

# Image reference for installing hive. See hive_install.sh.
#export HIVE_DEPLOY_IMAGE="registry.svc.ci.openshift.org/openshift/hive-v4.0:hive"
