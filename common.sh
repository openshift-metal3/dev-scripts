#!/bin/bash

export PATH="/usr/local/go/bin:$PATH"

eval "$(go env)"

export PATH="${GOPATH}/bin:$PATH"

# Workaround for https://github.com/containers/libpod/issues/3463
unset XDG_RUNTIME_DIR

# Ensure if a go program crashes we get a coredump
#
# To get the dump, use coredumpctl:
#   coredumpctl -o oc.coredump dump /usr/local/bin/oc
#
export GOTRACEBACK=crash

# Do not use pigz due to race condition in vendored docker code
# that oc uses.
# See: https://github.com/openshift/oc/issues/58,
#      https://github.com/moby/moby/issues/39859
export MOBY_DISABLE_PIGZ=true

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
USER=`whoami`

# Get variables from the config file
if [ -z "${CONFIG:-}" ]; then
    # See if there's a config_$USER.sh in the SCRIPTDIR
    if [ -f ${SCRIPTDIR}/config_${USER}.sh ]; then
        echo "Using CONFIG ${SCRIPTDIR}/config_${USER}.sh"
        CONFIG="${SCRIPTDIR}/config_${USER}.sh"
    else
        echo "Please run with a configuration environment set."
        echo "eg CONFIG=config_example.sh ./01_all_in_one.sh"
        exit 1
    fi
fi
source $CONFIG

# Provisioning network information
export PROVISIONING_NETWORK=${PROVISIONING_NETWORK:-172.22.0.0/24}
export PROVISIONING_NETMASK=${PROVISIONING_NETMASK:-$(ipcalc --netmask $PROVISIONING_NETWORK | cut -d= -f2)}
export CLUSTER_PRO_IF=${CLUSTER_PRO_IF:-enp1s0}

export BASE_DOMAIN=${BASE_DOMAIN:-test.metalkube.org}
export CLUSTER_NAME=${CLUSTER_NAME:-ostest}
export CLUSTER_DOMAIN="${CLUSTER_NAME}.${BASE_DOMAIN}"
export SSH_PUB_KEY="${SSH_PUB_KEY:-$(cat $HOME/.ssh/id_rsa.pub)}"
export NETWORK_TYPE=${NETWORK_TYPE:-"OpenShiftSDN"}
export EXTERNAL_SUBNET=${EXTERNAL_SUBNET:-"192.168.111.0/24"}
export CLUSTER_SUBNET=${CLUSTER_SUBNET:-"10.128.0.0/14"}
export CLUSTER_HOST_PREFIX=${CLUSTER_HOST_PREFIX:-"23"}
export SERVICE_SUBNET=${SERVICE_SUBNET:-"172.30.0.0/16"}
export DNS_VIP=${DNS_VIP:-"192.168.111.2"}
export LOCAL_REGISTRY_DNS_NAME=${LOCAL_REGISTRY_DNS_NAME:-"virthost.${CLUSTER_NAME}.${BASE_DOMAIN}"}

# ipcalc on CentOS 7 doesn't support the 'minaddr' option, so use python
# instead to get the first address in the network:
export PROVISIONING_HOST_IP=${PROVISIONING_HOST_IP:-$(python -c "import ipaddress; print(next(ipaddress.ip_network(u\"$PROVISIONING_NETWORK\").hosts()))")}
export PROVISIONING_HOST_EXTERNAL_IP=${PROVISIONING_HOST_EXTERNAL_IP:-$(python -c "import ipaddress; print(next(ipaddress.ip_network(u\"$EXTERNAL_SUBNET\").hosts()))")}
export MIRROR_IP=${MIRROR_IP:-$PROVISIONING_HOST_IP}

# mirror images for installation in restricted network
export MIRROR_IMAGES=${MIRROR_IMAGES:-}

WORKING_DIR=${WORKING_DIR:-"/opt/dev-scripts"}

# variables for local registry configuration
export LOCAL_REGISTRY_PORT=${LOCAL_REGISTRY_PORT:-"5000"}
export REGISTRY_USER=${REGISTRY_USER:-ocp-user}
export REGISTRY_PASS=${REGISTRY_PASS:-ocp-pass}
export REGISTRY_DIR=${REGISTRY_DIR:-$WORKING_DIR/registry}
export REGISTRY_CREDS=${REGISTRY_CREDS:-$HOME/private-mirror.json}

# Set this variable to build the installer from source
export KNI_INSTALL_FROM_GIT=${KNI_INSTALL_FROM_GIT:-}

#
# See https://openshift-release.svc.ci.openshift.org for release details
#
# if we provide OPENSHIFT_RELEASE_IMAGE, do not curl. This is needed for offline installs
if [ -z "${OPENSHIFT_RELEASE_IMAGE:-}" ]; then
  LATEST_CI_IMAGE=$(curl https://openshift-release.svc.ci.openshift.org/api/v1/releasestream/4.4.0-0.ci/latest | grep -o 'registry.svc.ci.openshift.org[^"]\+')
fi
export OPENSHIFT_RELEASE_IMAGE="${OPENSHIFT_RELEASE_IMAGE:-$LATEST_CI_IMAGE}"
export OPENSHIFT_INSTALL_PATH="$GOPATH/src/github.com/openshift/installer"

# Switch Container Images to upstream, Installer defaults these to the openshift version
if [ "${UPSTREAM_IRONIC:-false}" != "false" ] ; then
    export IRONIC_LOCAL_IMAGE=${IRONIC_LOCAL_IMAGE:-"quay.io/metal3-io/ironic:master"}
    export IRONIC_INSPECTOR_LOCAL_IMAGE=${IRONIC_INSPECTOR_LOCAL_IMAGE:-"quay.io/metal3-io/ironic-inspector:master"}
    export IRONIC_IPA_DOWNLOADER_LOCAL_IMAGE=${IRONIC_IPA_DOWNLOADER_LOCAL_IMAGE:-"quay.io/metal3-io/ironic-ipa-downloader:master"}
    export IRONIC_STATIC_IP_MANAGER_LOCAL_IMAGE=${IRONIC_STATIC_IP_MANAGER_LOCAL_IMAGE:-"quay.io/metal3-io/static-ip-manager"}
    export BAREMETAL_OPERATOR_LOCAL_IMAGE=${BAREMETAL_OPERATOR_LOCAL_IMAGE:-"quay.io/metal3-io/baremetal-operator"}
fi

if [ -z "$KNI_INSTALL_FROM_GIT" ]; then
    export OPENSHIFT_INSTALLER=${OPENSHIFT_INSTALLER:-ocp/openshift-baremetal-install}
 else
    export OPENSHIFT_INSTALLER=${OPENSHIFT_INSTALLER:-$OPENSHIFT_INSTALL_PATH/bin/openshift-install}

    # This is an URI so we can use curl for either the file on GitHub, or locally
    export OPENSHIFT_INSTALLER_MACHINE_OS=${OPENSHIFT_INSTALLER_MACHINE_OS:-file:///$OPENSHIFT_INSTALL_PATH/data/data/rhcos.json}

    # The installer defaults to origin/CI releases, e.g registry.svc.ci.openshift.org/origin/release:4.4
    # Which currently don't work for us ref
    # https://github.com/openshift/ironic-inspector-image/pull/17
    # Until we can align OPENSHIFT_RELEASE_IMAGE with the installer default, we still need
    # to set OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE for openshift-install source builds
    export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="${OPENSHIFT_RELEASE_IMAGE}"
fi

if env | grep -q "_LOCAL_IMAGE=" ; then
    export MIRROR_IMAGES=true
fi

if [ -n "$MIRROR_IMAGES" ]; then
    # We're going to be using a locally modified release image
    export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/local-release-image:latest"
fi

# Set variables
# Additional DNS
ADDN_DNS=${ADDN_DNS:-}
# External interface for routing traffic through the host
EXT_IF=${EXT_IF:-}
# Provisioning interface
PRO_IF=${PRO_IF:-}
# Does libvirt manage the baremetal bridge (including DNS and DHCP)
MANAGE_BR_BRIDGE=${MANAGE_BR_BRIDGE:-y}
# Only manage bridges if is set
MANAGE_PRO_BRIDGE=${MANAGE_PRO_BRIDGE:-y}
MANAGE_INT_BRIDGE=${MANAGE_INT_BRIDGE:-y}
# Internal interface, to bridge virbr0
INT_IF=${INT_IF:-}
#Root disk to deploy coreOS - use /dev/sda on BM
ROOT_DISK_NAME=${ROOT_DISK_NAME-"/dev/sda"}

FILESYSTEM=${FILESYSTEM:="/"}

NODES_FILE=${NODES_FILE:-"${WORKING_DIR}/ironic_nodes.json"}
NODES_PLATFORM=${NODES_PLATFORM:-"libvirt"}
BAREMETALHOSTS_FILE=${BAREMETALHOSTS_FILE:-"ocp/baremetalhosts.json"}

# Optionally set this to a path to use a local dev copy of
# metal3-dev-env, otherwise it's cloned to $WORKING_DIR
export METAL3_DEV_ENV=${METAL3_DEV_ENV:-}
if [ -z "${METAL3_DEV_ENV}" ]; then
  export VM_SETUP_PATH="${WORKING_DIR}/metal3-dev-env/vm-setup"
else
  export VM_SETUP_PATH="${METAL3_DEV_ENV}/vm-setup"
fi

export NUM_MASTERS=${NUM_MASTERS:-"3"}
export NUM_WORKERS=${NUM_WORKERS:-"1"}
export VM_EXTRADISKS=${VM_EXTRADISKS:-"false"}

# Ironic vars (Image can be use <NAME>_LOCAL_IMAGE to override)
export IRONIC_IMAGE="quay.io/metal3-io/ironic:master"
export IRONIC_IPA_DOWNLOADER_IMAGE="quay.io/metal3-io/ironic-ipa-downloader:master"
export IRONIC_DATA_DIR="${WORKING_DIR}/ironic"
export IRONIC_IMAGES_DIR="${IRONIC_DATA_DIR}/html/images"

# VBMC and Redfish images
export VBMC_IMAGE=${VBMC_IMAGE:-"quay.io/metal3-io/vbmc"}
export SUSHY_TOOLS_IMAGE=${SUSHY_TOOLS_IMAGE:-"quay.io/metal3-io/sushy-tools"}

export KUBECONFIG="${SCRIPTDIR}/ocp/auth/kubeconfig"

# Use a cloudy ssh that doesn't do Host Key checking
export SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"

# Verify requisites/permissions
# Connect to system libvirt
export LIBVIRT_DEFAULT_URI=qemu:///system
if [ "$USER" != "root" -a "${XDG_RUNTIME_DIR:-}" == "/run/user/0" ] ; then
    echo "Please use a non-root user, WITH a login shell (e.g. su - USER)"
    exit 1
fi

# Check if sudo privileges without password
if ! sudo -n uptime &> /dev/null ; then
  echo "sudo without password is required"
  exit 1
fi

# Check OS
if [[ ! $(awk -F= '/^ID=/ { print $2 }' /etc/os-release | tr -d '"') =~ ^(centos|rhel)$ ]]; then
  echo "Unsupported OS"
  exit 1
fi

# Check CentOS version
VER=$(awk -F= '/^VERSION_ID=/ { print $2 }' /etc/os-release | tr -d '"' | cut -f1 -d'.')
if [[ ${VER} -ne 7 ]] && [[ ${VER} -ne 8 ]]; then
  echo "Required CentOS 7 / RHEL 7 / RHEL 8"
  exit 1
fi

if grep -q "Red Hat Enterprise Linux release 8" /etc/redhat-release 2>/dev/null ; then
    export RHEL8="True"
fi

# Check d_type support
FSTYPE=$(df "${FILESYSTEM}" --output=fstype | tail -n 1)

case ${FSTYPE} in
  'ext4'|'btrfs')
  ;;
  'xfs')
    if [[ $(xfs_info ${FILESYSTEM} | grep -q "ftype=1") ]]; then
      echo "XFS filesystem must have ftype set to 1"
      exit 1
    fi
  ;;
  *)
    echo "Filesystem not supported"
    exit 1
  ;;
esac

# avoid "-z $PULL_SECRET" to ensure the secret is not logged
if [ ${#PULL_SECRET} = 0 ]; then
  echo "No valid PULL_SECRET set in ${CONFIG}"
  echo "Get a valid pull secret (json string) from https://cloud.openshift.com/clusters/install#pull-secret"
  exit 1
fi

if [ ! -d "$WORKING_DIR" ]; then
  echo "Creating Working Dir"
  sudo mkdir -p "$WORKING_DIR"
  sudo chown "${USER}:${USER}" "$WORKING_DIR"
  chmod 755 "$WORKING_DIR"
fi

if [ ! -d "$IRONIC_IMAGES_DIR" ]; then
  echo "Creating Ironic Images Dir"
  sudo mkdir -p "$IRONIC_IMAGES_DIR"
fi

# Previously the directory was owned by root, we need to alter
# permissions to be owned by the user running dev-scripts.
if [ ! -f "$IRONIC_IMAGES_DIR/.permissions" ]; then
  echo "Resetting permissions on Ironic Images Dir..."
  sudo chown -R "${USER}:${USER}" "$IRONIC_DATA_DIR"
  sudo find "$IRONIC_DATA_DIR" -type d -print0 | xargs -0 chmod 755
  sudo chmod -R +r "$IRONIC_DATA_DIR"
  touch "$IRONIC_IMAGES_DIR/.permissions"
fi

# Defaults the variable to enable testing a custom machine-api-operator image
export TEST_CUSTOM_MAO=${TEST_CUSTOM_MAO:-false}
