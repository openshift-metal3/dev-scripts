#!/bin/bash

################################################################################
## Development Settings
##

# CI_TOKEN - **REQUIRED**
# You can get this token from https://console-openshift-console.apps.ci.l2s4.p1.openshiftapps.com/
# by clicking on your name in the top right corner and coping the login
# command (the token is part of the command)
set +x
export CI_TOKEN=''
set -x

# CI_SERVER -
# When testing e.g cluster-bot builds, you must change CI_TOKEN to one
# from a different cluster, in which case this should be updated
#
#export CI_SERVER=api.ci.l2s4.p1.openshiftapps.com

# WORKING_DIR -
# By default, dev-scripts' working directory is set to `/opt/dev-scripts`.
# Make sure that the filesystem has at least 80GB of free space: `df -h /`.
# Alternatively you may have a large `/home` filesystem, in which case you can
# `export WORKING_DIR=/home/dev-scripts` and the scripts will create this directory
# with appropriate permissions. In the event you create this directory manually it
# should be world-readable (`chmod 755`) and `chown`ed by the non-root `$USER`.
#
#export WORKING_DIR=/home/dev-scripts

# OPENSHIFT_RELEASE_STREAM -
# Select a different release stream from which to pull the latest image, if the
# image name is not specified.
# Default: 4.17
# NOTE: Do not use for arm64, instead override OPENSHIFT_RELEASE_IMAGE
#
#export OPENSHIFT_RELEASE_STREAM=4.17

# OPENSHIFT_RELEASE_TYPE -
# Select a different release type from which to pull the latest image.
# If using ga then set OPENSHIFT_VERSION to the required version.
# Default: nightly
# Choices: ci, nightly, ga, okd
# NOTE: Do not use for arm64, instead override OPENSHIFT_RELEASE_IMAGE
# NOTE: If set to okd, a OPENSHIFT_RELEASE_IMAGE is required. See the below
# section on OPENSHIFT_RELEASE_IMAGE for an example.
#
#export OPENSHIFT_RELEASE_TYPE=nightly

# OPENSHIFT_RELEASE_IMAGE -
# Define a specific image to deploy the cluster from. If using OKD,
# this can be set to an image from: https://amd64.origin.releases.ci.openshift.org
# For example:
# export OPENSHIFT_RELEASE_IMAGE=registry.ci.openshift.org/origin/release:4.15.0-0.okd-2023-08-29-101209
# Default: Undefined

# OPENSHIFT_VERSION -
# Set the Openshift version. If unset defaults to $OPENSHIFT_RELEASE_STREAM.
# NOTE: Do not use for arm64, instead override OPENSHIFT_RELEASE_IMAGE
#
#export OPENSHIFT_VERSION=4.12

# *_LOCAL_IMAGE -
# Use <NAME>_LOCAL_IMAGE to build or use copy of container images locally e.g.
#
#export IRONIC_LOCAL_IMAGE=https://github.com/metal3-io/ironic
#export IRONIC_LOCAL_IMAGE=quay.io/username/ironic
#export MACHINE_CONFIG_OPERATOR_LOCAL_IMAGE=https://github.com/openshift/machine-config-operator
#
# NOTE: If a checkout already exists in $HOME, it won't be re-created.
# NOTE: You must set CUSTOM_REPO_FILE to build some OpenShift images, e.g. ironic ones.
# NOTE: The use of IRONIC_INSPECTOR_LOCAL_IMAGE is limited to Openshift up to
# Version 4.8, starting from Openshift 4.9 the ironic-inspector container is not used anymore.

# *_EXTRA_PACKAGES -
# Use <IMAGE_NAME>_EXTRA_PACKAGES to set the path (relative to dev-scripts or
# absolute) to a file with extra packages to install in the image, one per line.
# At the moment, this option is supported with ironic-image and
# ironic-inspector-image (NOTE: the ironic-inspector container has been
# removed in Openshift 4.9)
#
# For example:
# export IRONIC_EXTRA_PACKAGES=ironic-extra-pkgs.txt

# CUSTOM_BASE_IMAGE -
# Uncomment this to build a custom base image for ironic images
# Default is unset
#
# export CUSTOM_BASE_IMAGE=true

# BASE_IMAGE_DIR -
# Set this variable to point the custom base image to a different location
# It can be an absolute path or a local path under the dev-scripts dir
#
# export BASE_IMAGE_DIR=base-image

# CUSTOM_REPO_FILE, BASE_IMAGE_FROM, IRONIC_PR -
# To build custom images based on custom base images with custom repositories
# put all the custom repositories in a .repo file inside the base-image directory
# (default to dev-scripts/base-image) and set this variable with the name of the
# .repo file, e.g. if the filename is ocp46.repo
# export CUSTOM_REPO_FILE=ocp46.repo
#
# We can also change the very image the base-image is built from using the BASE_IMAGE_FROM
# variable; when we choose this, the repos included in the base image won't be removed.
#
# export BASE_IMAGE_FROM=centos:8
#
# If needed, we can fetch the change associated to a Pull Request for the images
# we're building locally. Specifying the PR number will fetch the PR, switch the
# local image repo to it, and build the image locally with that specific change.
# For example, for the PR #34 for the ironic-image:
#
# export IRONIC_PR=34

# UPSTREAM_IRONIC -
# Switch to upstream metal3-io ironic images instead of openshift ones.
#
#export UPSTREAM_IRONIC=true

# INSTALL_OPERATOR_SDK -
# Install operator-sdk for local testing of baremetal-operator
#
#export INSTALL_OPERATOR_SDK=1

# TEST_CUSTOM_MAO
# Enable testing of custom machine-api-operator-image. Default is false
#
#export TEST_CUSTOM_MAO=true

# CUSTOM_MAO_IMAGE
# Custom machine-api-operator image with tag
#
#export CUSTOM_MAO_IMAGE="quay.io/mao-user/machine-api-operator:mao-fix"

# REPO_NAME
# Git repository that is holding any custom machine-api-operator changes
#
#export REPO_NAME="mao-user"

# MAO_BRANCH
# Name of branch in the above repo which contains the custom MAO changes
#
#export MAO_BRANCH="mao-fix"

# Go version
# The version of go to be installed. The default value is 1.21.7
#
#export GO_VERSION="1.21.6"

################################################################################
## General Settings
##

# ROOT_DISK_NAME (Depreciated?)
# Which disk to deploy
#
#export ROOT_DISK_NAME="/dev/sda"

# CLUSTER_NAME - Openshift Cluster Name
# Default: "ostest"
#
#export CLUSTER_NAME="mycluster"

# BASE_DOMAIN - Base Domain name for the OCP cluster
# Default: "test.metalkube.org"
#
#export BASE_DOMAIN="kni.lab.metal3.io"

# IGNITION_EXTRA -
# Provide additional master/worker ignition configuration, will be
# merged with the installer provided config, can be used to modify
# the default nic configuration etc
#
#export IGNITION_EXTRA=extra.ign

# ASSETS_EXTRA_FOLDER -
# Folder where to copy extra manifests for the cluster deployment
# If dev-scripts is running with a local registry enabled, any container images
# referenced will be mirrored and the container updated to reference the mirror
#
#export ASSETS_EXTRA_FOLDER=local_file_path

# FIPS_MODE
# Enable FIPS mode
#
#export FIPS_MODE=true

# DISABLE_MULTICAST -
# In order to test using unicast for keepalived, one needs to disable multicast.
# Setting this variable to true will block multicast via ebtables for both IPv4
# and IPv6.
#
#export DISABLE_MULTICAST=false

# ENABLE_METALLB_MODE -
# Enable metallb
# Default is unset.
# Choices: "l2", "bgp"
#
#export ENABLE_METALLB_MODE="l2"
#
# metallb container location (optional)
#export METALLB_IMAGE_BASE=
#export METALLB_IMAGE_TAG=

# PERSISTENT_IMAGEREG
# Default: false
# Enables dev-scripts to setup and use nfs on the host as persistent storage
# for the cluster image-registry
# export PERSISTENT_IMAGEREG=true

################################################################################
## Network Settings
##

# You can set IP_STACK to "v4" or "v6" and HOST_IP_STACK to "v4v6" to install a
# single-stack cluster on dual-stack hosts.

# IP_STACK -
# IP stack for the cluster. "v4v6" is ipv4-primary dual stack, "v6v4" is
# ipv6-primary dual stack.
# NOTE: arm64 does not support v6
# Default: "v6"
# Choices: "v4", "v6", "v4v6", "v6v4"
#
#export IP_STACK=v4

# HOST_IP_STACK -
# IP stack for the host.
# Default: If unset, defaults to ${IP_STACK}.
# NOTE: arm64 does not support v6
# Choices: "v4", "v6", "v4v6"
#
#export HOST_IP_STACK=v4v6

# NTP_SERVERS - Configure custom ntp servers if needed
# Default is unset.
#
#export NTP_SERVERS="00.my.internal.ntp.server.com;01.other.ntp.server.com"

# PROVISIONING_NETWORK_PROFILE
# Select the provisioning network profile to use. If set to Disabled the
# PROVISIONING_IP_SUBNET is set to the EXTERNAL_IP_SUBNET. If set to Managed
# this is managed by DHCP.
# Default: "Managed"
# Choices: "Managed", "Disabled"
#
#export PROVISIONING_NETWORK_PROFILE=Managed

# Provisioning interface on the helper node
#export PRO_IF="eno1"

# Internal interface
#export INT_IF="eno2"

# Provisioning interface within the cluster (Default: "enp1s0")
#export CLUSTER_PRO_IF="eno1"

# Manage bridge
#export MANAGE_BR_BRIDGE=n

# Enable virtualMediaViaExternalNetwork in provisioning configuration.
# More info: https://github.com/openshift/cluster-baremetal-operator/blob/master/api/v1alpha1/provisioning_types.go#L163-L171
#export ENABLE_VIRTUAL_MEDIA_VIA_EXTERNAL_NETWORK=true

# Set the DHCP lease time (Default: 60)
#export DHCP_LEASE_EXPIRY=60

# DNS_VIP -
# Set the DNS VIP for the Openshift cluster.
# The value selected is based off the value of IP_STACK.
#
# v4 Default:
#export DNS_VIP="11.0.0.2"
#
# v6 Default:
#export DNS_VIP="fd2e:6f44:5dd8:c956::2"
#
# v4v6 Default:
#export DNS_VIP="fd2e:6f44:5dd8:c956::2"

# NETWORK_TYPE -
# Set the network type for the Openshift cluster.
# The value selected is based off the value of IP_STACK.
#
# v4 Default:
#export NETWORK_TYPE="OpenShiftSDN"
#
# v6 Default:
#export NETWORK_TYPE="OVNKubernetes"
#
# v4v6 Default:
#export NETWORK_TYPE="OVNKubernetes"

# CLUSTER_SUBNET
# Set the cluster subnet CIDR for the Openshift cluster.
# The value selected is based off the value of IP_STACK.
#
# v4 Default:
#export CLUSTER_SUBNET_V4="10.128.0.0/14"
#export CLUSTER_SUBNET_V6=""
#
# v6 Default:
#export CLUSTER_SUBNET_V4=""
#export CLUSTER_SUBNET_V6="fd01::/48"
#
# v4v6 Default:
#export CLUSTER_SUBNET_V4="10.128.0.0/14"
#export CLUSTER_SUBNET_V6="fd01::/48"

# CLUSTER_HOST_PREFIX -
# Set the cluster host prefix for the Openshift cluster.
# The value selected is based off the value of IP_STACK.
#
# v4 Default:
#export CLUSTER_HOST_PREFIX_V4="23"
#export CLUSTER_HOST_PREFIX_V6=""
#
# v6 Default:
#export CLUSTER_HOST_PREFIX_V4=""
#export CLUSTER_HOST_PREFIX_V6="64"
#
# v4v6 Default:
#export CLUSTER_HOST_PREFIX_V4="23"
#export CLUSTER_HOST_PREFIX_V6="64"

# SERVICE_SUBNET (Defaults to v6)
# Set the service subnet CIDR for the cluster to use.
# The value selected is based off the value of IP_STACK.
#
# v4 Default:
#export SERVICE_SUBNET_V4="172.30.0.0/16"
#export SERVICE_SUBNET_V6=""
#
# v6 Default:
#export SERVICE_SUBNET_V4=""
#export SERVICE_SUBNET_V6="fd02::/112"
#
# v4v6 Default:
#export SERVICE_SUBNET_V4="172.30.0.0/16"
#export SERVICE_SUBNET_V6="fd02::/112"

# PROVISIONING_NETWORK -
# Set the provisiong network CIDR for the Openshift cluster.
# The value selected is based off the value of HOST_IP_STACK.
#
# v4 Provisioning network
#export PROVISIONING_NETWORK="172.23.0.0/16"
#
# v6 Provisioning network
#export PROVISIONING_NETWORK=fd00:1101::0/64
#
# v4v6 Provisioning network
#export PROVISIONING_NETWORK="172.23.0.0/16"

# Extra Network(s)
# Provision one or more extra networks for each host.
# Each new network will be connected to an addition interface on each host.
# The hosts will automatically name the interface(s) connected to the network.
# EXTRA_NETWORK_NAMES array may contain any name you wish and each new
# network name must have a corresponding subnet.
#
#export EXTRA_NETWORK_NAMES="nmstate1 nmstate2"
#export NMSTATE1_NETWORK_SUBNET_V4='192.168.221.0/24'
#export NMSTATE1_NETWORK_SUBNET_V6='fd2e:6f44:5dd8:ca56::/120'
#export NMSTATE2_NETWORK_SUBNET_V4='192.168.222.0/24'
#export NMSTATE2_NETWORK_SUBNET_V6='fd2e:6f44:5dd8:cc56::/120'

# EXTERNAL_SUBNET -
# Set the external subnet CIDR for the Openshift cluster.
# The value selected is based off the value of HOST_IP_STACK.
#
# v4 Default:
#export EXTERNAL_SUBNET_V4="11.0.0.0/24"
#export EXTERNAL_SUBNET_V6=""
#
# v6 Default:
#export EXTERNAL_SUBNET_V4=""
#export EXTERNAL_SUBNET_V6="fd2e:6f44:5dd8:c956::/120"
#
# v4v6 Default:
#export EXTERNAL_SUBNET_V4="11.0.0.0/24"
#export EXTERNAL_SUBNET_V6="fd2e:6f44:5dd8:c956::/120"

# ENABLE_BOOTSTRAP_STATIC_IP -
# Configure a static IP for the bootstrap VM external NIC
# (Currently this just expects a non-empty value, the IP is fixed to .9)
# export ENABLE_BOOTSTRAP_STATIC_IP=true

# A MAC address to use for the external NIC on the bootstrap VM.
# EXTERNAL_BOOTSTRAP_MAC=52:54:00:00:11:22

# NETWORK_CONFIG_FOLDER -
# Set this to the location of a folder containing networkConfigs for the nodes
# in the deployment. The filenames correspond to the name of the host. For
# example, to provide a networkConfig for master-0 in a default dev-scripts
# deployment, create a file named `ostest-master-0.yaml` in the specified
# folder that contains the networkConfig (including the key "networkConfig").
#
# This folder may also contain a file named `hosts.yaml` which is a list of
# additional DNS entries to configure in the libvirt DNS. This should be a
# list of entries with the following format:
# - ip: 192.168.111.110
#   hostnames:
#     - "master-0"

# BOND_PRIMARY_INTERFACE -
# When set to any value this will cause dev-scripts to include duplicate nics
# on the primary network. This is intended for testing bonded network configs
# and may not work without a bond config.

################################################################################
## VM Settings
##

# BMC_DRIVER - BMC type.
# Default: redfish
# Choices: redfish, redfish-virtualmedia, ipmi
#
#export BMC_DRIVER=redfish-virtualmedia

# REDFISH_EMULATOR_IGNORE_BOOT_DEVICE -
# Instruct the redfish emulator to ignore any instructions to set the boot device
# Default: False
# Choices: True, False
#
#export REDFISH_EMULATOR_IGNORE_BOOT_DEVICE=False

# VM_TPM_EMULATOR -
# Add TPM2.0 emulator to VMs.
# Default is unset
#
# export VM_TPM_EMULATOR=true

# SSH_PUB_KEY -
# SSH key used to ssh into deployed hosts.  This must be the contents of the
# variable, not the filename. The contents of ~/.ssh/id_rsa.pub are used by
# default.
#
#export SSH_PUB_KEY=$(cat ~/.ssh/id_rsa.pub)

# NODES_FILE -
# Path to the json files with ipmi credentials
# Default: "$WORKING_DIR/$CLUSTER_NAME/ironic_nodes.json"
#
#export NODES_FILE="/root/git/dev-scripts/bm.json"

# NODES_PLATFORM -
# Whether the installation is on baremetal or not
# Default is unset.
#
#export NODES_PLATFORM=baremetal

# MASTER_HOSTNAME_FORMAT -
# Set a custom hostname format for masters. This is a format string that should
# include one %d field, which will be replaced with the number of the node.
# Default: "master-%d"
#
#export MASTER_HOSTNAME_FORMAT=master-%d

# NUM_MASTERS -
# Indicate number of master nodes to deploy.
# Default: 3
#
#export NUM_MASTERS=3

# MASTER_MEMORY, MASTER_DISK, MASTER_VCPU -
# Change VM resources for masters
## Defaults:
## MASTER_DISK=30
## MASTER_MEMORY=16384
## MASTER_VCPU=8
#
#export MASTER_MEMORY=16384
#export MASTER_DISK=40
#export MASTER_VCPU=8

# WORKER_HOSTNAME_FORMAT -
# Set a custom hostname format for workers. This is a format string that should
# include one %d field, which will be replaced with the number of the node.
# Default: "worker-%d".
#
#export WORKER_HOSTNAME_FORMAT=worker-%d

# NUM_WORKERS -
# Indicate number of worker nodes to deploy.
# Default: 2
#
#export NUM_WORKERS=0

# WORKER_MEMORY, WORKER_DISK, WORKER_VCPU -
# Change VM resources for workers.
## Defaults:
## WORKER_DISK=30
## WORKER_MEMORY=8192
## WORKER_VCPU=4
#
#export WORKER_MEMORY=8192
#export WORKER_DISK=30
#export WORKER_VCPU=4

# NUM_EXTRA_WORKERS - Indicate number of extra VMs to create but not deploy.
# Default: 0
#
#export NUM_EXTRA_WORKERS=0

# EXTRA_WORKER_MEMORY, EXTRA_WORKER_DISK, EXTRA_WORKER_VCPU -
# Change VM resources for extra workers. If not supplied defaults to the
# regular workers specs.
## Defaults:
## EXTRA_WORKER_DISK=30
## EXTRA_WORKER_MEMORY=8192
## EXTRA_WORKER_VCPU=4
#
#export EXTRA_WORKER_MEMORY=8192
#export EXTRA_WORKER_DISK=30
#export EXTRA_WORKER_VCPU=4

# EXTRA_WORKERS_ONLINE_STATUS -
# Indicate the online status of the NUM_EXTRA_WORKERS set in extra_host_manifests.yaml
# Default: true
#
#export EXTRA_WORKERS_ONLINE_STATUS=true

# APPLY_EXTRA_WORKERS -
# Apply extra workers to the cluster if NUM_EXTRA_WORKERS is set
# Default is unset.
#
#export APPLY_EXTRA_WORKERS=true.

# VM_EXTRADISKS - Add extradisks to VMs
# Default: false
#
# export VM_EXTRADISKS=true

# VM_EXTRADISKS_LIST -
# Configure how many extra disks to add to VMs. Takes a string of disk
# names delimited by spaces. Example "vdb vdc".
# Default: "vdb"
#
# export VM_EXTRADISKS_LIST="vdb vdc"

# VM_EXTRADISKS_SIZE -
# Configure size of extra disks added to VMs.
# Default: "8G"
#
# export VM_EXTRADISKS_SIZE="10G"

################################################################################
## Image Registry Settings
##

# ENABLE_LOCAL_REGISTRY -
# Ensure that the local registry will be available
# Default is unset.
#
#export ENABLE_LOCAL_REGISTRY=true

# REGISTRY_BACKEND
# Define the local registry to use when ENABLE_LOCAL_REGISTRY=true
# The default (legacy) registry is started by podman
# The other available backend is quay which is installed by the
# mirror-registry application
# Default: podman
# Choices: podman, quay
# export REGISTRY_BACKEND=podman

# LOCAL_REGISTRY_DNS_NAME -
# Local image registry DNS name.
# Default: "virthost.$CLUSTER_NAME.test.metalkube.org"
#
#export LOCAL_REGISTRY_DNS_NAME="virthost.ostest.test.metalkube.org"

# LOCAL_REGISTRY_PORT -
# Local image registry port.
# Default: 5000
#
#export LOCAL_REGISTRY_PORT="5000"

# REGISTRY_USER, REGISTRY_PASS -
# Configure username and password for local registry
#
#export REGISTRY_PASS=some-pass
#export REGISTRY_USER=some-user

# REGISTRY_DIR -
# Configure base directory for local registry
# Default: "$WORKING_DIR/registry"
#
#export REGISTRY_DIR=/opt/registry

# REGISTRY_CREDS -
# Configure location of registry mirror's creds
# Default: "$HOME/$USER-private-mirror-$CLUSTER_NAME.json"
#
#export REGISTRY_CREDS=${REGISTRY_CREDS:-$USER/private-mirror.json}

# MIRROR_IMAGES -
# Mirror latest ci images to local registry. This is true by default for IPv6, but
# can be turned on for an IPv4 install. To explicitly disable set it to false.
# Default: true
#
#export MIRROR_IMAGES=true

# MIRROR_COMMAND -
# When MIRROR_IMAGES is true, this identifies the command that will create the mirror
# Can be either:
# - oc-adm - use the 'oc adm release mirror' command
# - oc-mirror - use the 'oc mirror' command
# Default: oc-adm
#export MIRROR_COMMAND=oc-adm

# OC_MIRROR_TO_FILE -
# When MIRROR_IMAGES is true and MIRROR_COMMAND is oc-mirror, if this is set it
# will cause the mirror to be generated in a 2-step process. First the contents of
# the mirror is stored in a tarfile and then the tarfile is published to the registry
# Default is unset

# When the MIRROR_COMMAND is set to 'oc-mirror' the auths for the mirror will be added
# to DOCKER_CONFIG_FILE or an UNAUTHORIZED error will result.
# An example entry in this file is:
# "virthost.ostest.test.metalkube.org:LOCAL_REGISTRY_PORT=": { "auth": "<auth string>" },
#export DOCKER_CONFIG_FILE=$HOME/.docker/config.json

# MIRROR_OLM -
# Comma-separated list of OLM operators to mirror into the local registry. This
# has no effect if MIRROR_IMAGES is false. This will not work for releases that
# have not yet shipped. The content for the release must have been published in
# order for mirroring to work.
# Note - MIRROR_OLM is currently not supported when MIRROR_COMMAND=oc-mirror, it
# must be set to oc-adm
#
#export MIRROR_OLM="local-storage-operator,kubernetes-nmstate-operator"

# MIRROR_OLM_REMOTE_INDEX -
# OLM catalog index to be used instead of a default one.
# Default: "registry.redhat.io/redhat/redhat-operator-index:v${VERSION}"
#
#export MIRROR_OLM_REMOTE_INDEX="corp.example/registry/corp-operator-index:v2"

# MIRROR_CUSTOM_IMAGES -
# Comma-separated list of container images to mirror into the local registry. This
# has no effect if MIRROR_IMAGES is false.
#
#export MIRROR_CUSTOM_IMAGES="corp.example/registry/sample-app:v1"

################################################################################
## Multi-cluster/Hive variables
##

# HIVE_DEPLOY_IMAGE -
# Image reference for installing hive. See hive_install.sh.
# Default: "registry.ci.openshift.org/openshift/hive-v4.0:hive"
#
#export HIVE_DEPLOY_IMAGE="registry.ci.openshift.org/openshift/hive-v4.0:hive"

# ADDITIONAL_TRUST_BUNDLE -
# PEM-encoded X.509 certificate bundle that will be added to the nodes' trusted
# certificate store. This trust bundle may also be used when a proxy has
# been configured.
#
# export ADDITIONAL_TRUST_BUNDLE=/path/to/ca_file

# INSTALLER_PROXY -
# Configures the installer to use a proxy running on the local host
# and blocks all outgoing traffic.
# Default: ""
#
# export INSTALLER_PROXY=true

################################################################################
## Assisted Deployment
##

# The following variables will allow for setting a custom image to use for each
# of the components deployed by the Assisted Operator

# export ASSISTED_SERVICE_IMAGE="quay.io/ocpmetal/assisted-service:latest"
# export ASSISTED_INSTALLER_IMAGE="quay.io/ocpmetal/assisted-installer:latest"
# export ASSISTED_AGENT_IMAGE="quay.io/ocpmetal/assisted-installer-agent:latest"
# export ASSISTED_DATABASE_IMAGE="quay.io/ocpmetal/postgresql-12-centos7:latest"
# export ASSISTED_CONTROLLER_IMAGE="quay.io/ocpmetal/assisted-installer-controller:latest"

# Get the latest default versions from the assisted-service repo itself.
# export ASSISTED_OPENSHIFT_VERSIONS=$(wget -qO- https://raw.githubusercontent.com/openshift/assisted-service/master/default_ocp_versions.json)

# Operator's bundle index to use. This will allow for testing a custom Assisted operator build that has
# not been published yet. For custom Assisted Service images it's enough to overwrite one of the images above.
# Overwrite this image only if you are working on the operator itself.
# export ASSISTED_OPERATOR_INDEX="quay.io/ocpmetal/assisted-service-index:latest"

# The namespace to use for Assisted Service. Note that the assisted service also deploys Hive
# and the Local Storage oeprator. Hive's subscription will be deployed on the `openshift-operators`
# namespace and the Local Storage in the `openshift-local-storage` one.
# export ASSISTED_NAMESPACE="assisted-installer"

# Uncomment the following line to have BareMetal Operator watch the BareMetalHosts on all namespaces.
# Note that setting this variable to true will require more RAM. (Default: false)
# More info here: https://github.com/openshift-metal3/dev-scripts/pull/1241#issuecomment-846067822
# export BMO_WATCH_ALL_NAMESPACES="true"

# For platforms that use nmstate configuration, the bond mode is set to the value.
# The possible values are 'balance-rr', 'active-backup', 'broadcast', 'balance-xor',
# 'balance-tlb', and 'balance-alb'.
# The default is no bonding, so value is set to 'none'.
# export BOND_CONFIG='none'

################################################################################
## Agent Deployment
##

# Set whether static IPs will be used for all nodes or only Node0
# export AGENT_STATIC_IP_NODE0_ONLY="true"

# Set a single config variable AGENT_E2E_TEST_SCENARIO to create a cluster for the different scenarios
# i.e. Single Node Openshift(SNO), Highly Available (HA) or Compact cluster.
# The boot mode for the agent machines can only be set to ISO or PXE.
# For backward compatibility of CI jobs, the default boot mode is ISO.
# The only supported values for AGENT_E2E_TEST_SCENARIO are
# - COMPACT_IPV4
# - COMPACT_IPV6
# - COMPACT_IPV4_DHCP
# - COMPACT_IPV6_DHCP
# - HA_IPV4
# - HA_IPV6
# - HA_IPV4_DHCP
# - HA_IPV6 _DHCP
# - SNO_IPV4
# - SNO_IPV6
# - SNO_IPV4_DHCP
# - SNO_IPV6_DHCP
# When set, the code internally sets other low level details such as disk size, memory, number of masters and workers,
# cpu and ip stack.
# This config variable is used only by the agent based installer and is required.
# export AGENT_E2E_TEST_SCENARIO=COMPACT_IPV4_DHCP

# Uncomment the following line to deploy the MCE operator, and to automatically import the current cluster as the hub cluster
# export AGENT_DEPLOY_MCE=true

# Set the following value to true to supply ZTP manifests to the installer. By default the install-config.yaml/agent-config.yaml
# will be used as input to the installer.
# export AGENT_USE_ZTP_MANIFESTS=false

# Uncomment and set the following value to "true" to disable the automated
# deployment systemd services of the Agent based installation. This is
# particularly useful for WebUI development.
# export AGENT_DISABLE_AUTOMATED=false

# When set, the code internally sets the boot mode for the agents.
# This config variable is used only by the agent based installer and is optional.
# The default value for AGENT_E2E_TEST_BOOT_MODE is 'ISO'.
# For the openshift-appliance flow, set the boot mode to 'DISKIMAGE'.
# AGENT_E2E_TEST_BOOT_MODE=PXE

# Uncomment and set the following value to "true" to enable a test scenario
# where the DNS is disabled on the hosts by setting its IP address to an incorrect value.
# Uncomment and set the following value to one or more test cases below.
# Multiple test cases can be listed using ',' as the delimiter.
#
# 1. 'bad_dns' test case:
# The DNS is disabled on the hosts by setting its IP address to an incorrect value.
# This causes the agent-tui to reach a state where it remains up showing the
# release image cannot be reached and waits for the user to fix the issue.
# The test scenario adds a sleep after the VMs are booted and "waits" for the hosts to reach this state.
# After the sleep, it then invokes a series of console key presses to simulate a user fixing the issue
# through the console. The key presses should fix the issue and should allow the automated
# workflow to continue ending with a successful cluster installation. If it fails to fix the issue
# then the wait-for commands should timeout and fail.
# This test case is only supported when IP_STACK=v4.
#
# export AGENT_TEST_CASES='bad_dns'

# Uncomment the following line to deploy the cluster using the appliance model
# The appliance model boots the host using the unconfigured ignition. It then mounts
# the configuration ISO where its contents are copied over to the host. The cluster
# installation is triggered when the /etc/assisted/rendezvous-host.env file is present.
# export AGENT_USE_APPLIANCE_MODEL=false

# When the installation is done using the agent appliance the config-image can
# be added either when creating the VM or after the host has booted with the unconfigured
# ignition. This setting configures when the config-image is added, by default it will be
# adding when creating the VM.
# export AGENT_APPLIANCE_HOTPLUG=false

# Sets the install-config.yaml's platform type.
# The default is 'baremetal'.
# When set to 'none', the cluster is deployed using platform none.
# This means userManagedNetworking is set to true in AgentClusterInstall,
# and, if not set for SNO, haproxy is deployed as the load balancer, and the appropriate
# DNS records are created.
# Likewise when set to 'external', the cluster is deployed in the same way as 'none' with
# the addition of setting the manufacturer and product for the domain to ensure that
# the assisted-service validations pass.
# export AGENT_PLATFORM_TYPE=baremetal

# When set to 'oci', the CloudControllerManager field is set to External in the install-config.yaml.
# export AGENT_PLATFORM_NAME=oci

# When set to 'true', configure the host settings in agent-config.yaml to
# include the nmstate configuration when using DHCP.
# The default is 'false', in which case the nmstate configuration will
# not be included
# export AGENT_NMSTATE_DHCP=false

# When set to 'true', set the baremetal hosts field in install-config.yaml,
# not in agent-config.yaml. This is similar to baremetal IPI configuration.
# The default is 'false', in which case the hosts will be defined in
# agent-config.yaml.
# export AGENT_BM_HOSTS_IN_INSTALL_CONFIG=false

# AGENT_WAIT_FOR_INSTALL_COMPLETE
# Default: true
#
# Setting this to false skips the "wait-for install-complete" step.
#
# export AGENT_WAIT_FOR_INSTALL_COMPLETE=false

# Image reference for OpenShift-based Appliance Builder.
# See: https://github.com/openshift/appliance
# Default: "quay.io/edge-infrastructure/openshift-appliance:latest"
#
# export APPLIANCE_IMAGE="quay.io/edge-infrastructure/openshift-appliance:latest"

# Alternative local path to the metal3-dev-env repository.
# Optionally set this to a path to use a local dev copy of
# metal3-dev-env, otherwise it's cloned to $WORKING_DIR
# The location won't be synced or updated preserving any local
# changes applied to it.
# export METAL3_DEV_ENV=''
