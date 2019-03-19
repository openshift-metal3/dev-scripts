#!/bin/bash

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
USER=`whoami`

# Additional DNS
ADDN_DNS=${ADDN_DNS:-}
# External interface for routing traffic through the host
EXT_IF=${EXT_IF:-}
# Provisioning interface
PRO_IF=${PRO_IF:-}
# Internal interface, to bridge virbr0
INT_IF=${INT_IF:-}
#Root disk to deploy coreOS - use /dev/sda on BM
ROOT_DISK=${ROOT_DISK:="/dev/vda"}

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

# Use a cloudy ssh that doesn't do Host Key checking
export SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"

# Connect to system libvirt
export LIBVIRT_DEFAULT_URI=qemu:///system
if [ "$USER" != "root" -a "${XDG_RUNTIME_DIR:-}" == "/run/user/0" ] ; then
    echo "Please use a non-root user, WITH a login shell (e.g. su - USER)"
    exit 1
fi

WORKING_DIR=${WORKING_DIR:-"/opt/dev-scripts"}
NODES_FILE=${NODES_FILE:-"${WORKING_DIR}/ironic_nodes.json"}
NODES_PLATFORM=${NODES_PLATFORM:-"libvirt"}
MASTER_NODES_FILE=${MASTER_NODES_FILE:-"ocp/master_nodes.json"}

# avoid "-z $PULL_SECRET" to ensure the secret is not logged
if [ ${#PULL_SECRET} = 0 ]; then
  echo "No valid PULL_SECRET set in ${CONFIG}"
  echo "Get a valid pull secret (json string) from https://cloud.openshift.com/clusters/install#pull-secret"
  exit 1
fi

if [ ! -d "$WORKING_DIR" ]; then
    echo "Creating Working Dir"
    sudo mkdir "$WORKING_DIR"
    sudo chown "${USER}:${USER}" "$WORKING_DIR"
    sudo chmod 755 "$WORKING_DIR"
fi

export RHCOS_IMAGE_URL=${RHCOS_IMAGE_URL:-"https://releases-rhcos.svc.ci.openshift.org/storage/releases/maipo/"}
export RHCOS_IMAGE_VERSION="${RHCOS_IMAGE_VERSION:-400.7.20190312.0}"
export RHCOS_IMAGE_NAME="rhcos-maipo-${RHCOS_IMAGE_VERSION}"
# FIXME(shardy) note the -openstack image doesn't work for libvirt
# as the qemu ignition config injection described in the docs at
# https://coreos.com/os/docs/latest/booting-with-libvirt.html
# doesn't work - probably we need to download both as the
# -openstack one may be needed for the baremetal nodes so we get
# config drive support, or perhaps a completely new image?
export RHCOS_IMAGE_FILENAME="${RHCOS_IMAGE_NAME}-qemu.qcow2"
export RHCOS_IMAGE_FILENAME_OPENSTACK="${RHCOS_IMAGE_NAME}-openstack.qcow2"
export RHCOS_IMAGE_FILENAME_DUALDHCP="${RHCOS_IMAGE_NAME}-dualdhcp.qcow2"
export RHCOS_IMAGE_FILENAME_LATEST="redhat-coreos-maipo-latest.qcow2"

# Ironic vars
export IRONIC_IMAGE=${IRONIC_IMAGE:-"quay.io/metalkube/metalkube-ironic"}
export IRONIC_INSPECTOR_IMAGE=${IRONIC_INSPECTOR_IMAGE:-"quay.io/metalkube/metalkube-ironic-inspector"}
export IRONIC_DATA_DIR="$WORKING_DIR/ironic"

# Log output automatically
LOGDIR="$(dirname $0)/logs"
if [ ! -d "$LOGDIR" ]; then
    mkdir -p "$LOGDIR"
fi
LOGFILE="$LOGDIR/$(basename $0 .sh)-$(date +%F-%H%M%S).log"
echo "Logging to $LOGFILE"
# Set fd 1 and 2 to write to the log file
exec 1> >( tee "${LOGFILE}" ) 2>&1
