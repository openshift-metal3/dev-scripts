#!/bin/bash

export PATH="/usr/local/go/bin:$HOME/.local/bin:$PATH"

# Set a PS4 value which logs the script name and line #.
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

eval "$(go env)"

export PATH="${GOPATH}/bin:$PATH"

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
GROUP=`id -gn`

function error () {
    echo $@ 1>&2
}

is_lower_version () {
  if [[ $(echo "$1 $2" | tr " " "\n" | sort -V | head -n1) != $2 ]]; then
    return 0
  else
    return 1
  fi
}

XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$(systemd-path user-configuration)}

# Get variables from the config file
if [ -z "${CONFIG:-}" ]; then
    # See if there's a config_$USER.sh in the SCRIPTDIR
    if [ -f ${SCRIPTDIR}/config_${USER}.sh ]; then
        echo "Using CONFIG ${SCRIPTDIR}/config_${USER}.sh" 1>&2
        CONFIG="${SCRIPTDIR}/config_${USER}.sh"
    elif [[ -f "${XDG_CONFIG_HOME}/dev-scripts/config" ]]; then
        echo "Using CONFIG ${XDG_CONFIG_HOME}/dev-scripts/config" 1>&2
        CONFIG="${XDG_CONFIG_HOME}/dev-scripts/config"
    else
        error "Please run with a configuration environment set."
        error "eg CONFIG=config_example.sh ./01_all_in_one.sh"
        exit 1
    fi
fi
source $CONFIG

export CLUSTER_NAME=${CLUSTER_NAME:-ostest}

export PROVISIONING_NETWORK_PROFILE=${PROVISIONING_NETWORK_PROFILE:-"Managed"}

# Network interface names can only be 15 characters long, so
# abbreviate provisioning and baremetal and add them as suffixes to
# the cluster name.
export PROVISIONING_NETWORK_NAME=${PROVISIONING_NETWORK_NAME:-${CLUSTER_NAME}pr}
export BAREMETAL_NETWORK_NAME=${BAREMETAL_NETWORK_NAME:-${CLUSTER_NAME}bm}

export BASE_DOMAIN=${BASE_DOMAIN:-test.metalkube.org}
export CLUSTER_DOMAIN="${CLUSTER_NAME}.${BASE_DOMAIN}"
export SSH_PUB_KEY="${SSH_PUB_KEY:-$(cat $HOME/.ssh/id_rsa.pub)}"

# mirror images for installation in restricted network
export MIRROR_IMAGES=${MIRROR_IMAGES:-}
# For IPv6 (default case) mirror images are used since quay doesn't support IPv6
if [[ -z "${IP_STACK:-}" || "$IP_STACK" = "v6" || "$IP_STACK" = "v6v4" ]]; then
    export MIRROR_IMAGES=${MIRROR_IMAGES:-true}
fi

# identify the command used to mirror images, either 'oc-adm' or 'oc-mirror'
export MIRROR_COMMAND=${MIRROR_COMMAND:-oc-adm}

# mirror images for installation in restricted network
export OC_MIRROR_TO_FILE=${OC_MIRROR_TO_FILE:-}

# file containing auths for oc-mirror
export DOCKER_CONFIG_FILE=${DOCKER_CONFIG_FILE:-$HOME/.docker/config.json}

# Setup up a local proxy for installation
export INSTALLER_PROXY=${INSTALLER_PROXY:-}
export INSTALLER_PROXY_PORT=${INSTALLER_PROXY_PORT:-8215}

# Hypervisor details
export REMOTE_LIBVIRT=${REMOTE_LIBVIRT:-0}
export PROVISIONING_HOST_USER=${PROVISIONING_HOST_USER:-$USER}

# The dev-scripts working directory
export WORKING_DIR=${WORKING_DIR:-"/opt/dev-scripts"}
OCP_DIR=${OCP_DIR:-ocp/${CLUSTER_NAME}}

# The DNS name for the registry that this cluster should use.
export LOCAL_REGISTRY_DNS_NAME=${LOCAL_REGISTRY_DNS_NAME:-"virthost.${CLUSTER_NAME}.${BASE_DOMAIN}"}
# All DNS names for the registry, to be included in the certificate.
export ALL_REGISTRY_DNS_NAMES=${ALL_REGISTRY_DNS_NAMES:-${LOCAL_REGISTRY_DNS_NAME}}

# variables for local registry configuration
export LOCAL_REGISTRY_PORT=${LOCAL_REGISTRY_PORT:-"5000"}
export REGISTRY_USER=${REGISTRY_USER:-ocp-user}
export REGISTRY_PASS=${REGISTRY_PASS:-ocp-pass}
export REGISTRY_DIR=${REGISTRY_DIR:-$WORKING_DIR/registry}
export REGISTRY_CREDS=${REGISTRY_CREDS:-$HOME/private-mirror-${CLUSTER_NAME}.json}
export REGISTRY_CRT=registry.2.crt
export REGISTRY_BACKEND=${REGISTRY_BACKEND:-"podman"}

# Set this variable to build the installer from source
export KNI_INSTALL_FROM_GIT=${KNI_INSTALL_FROM_GIT:-}

export OPENSHIFT_CLIENT_TOOLS_URL=https://mirror.openshift.com/pub/openshift-v4/$(uname -m)/clients/ocp/stable/openshift-client-linux.tar.gz

# Note: when changing defaults for OPENSHIFT_RELEASE_STREAM, make sure to update
#       doc in config_example.sh
export OPENSHIFT_RELEASE_TYPE=${OPENSHIFT_RELEASE_TYPE:-nightly}
export OPENSHIFT_RELEASE_STREAM=${OPENSHIFT_RELEASE_STREAM:-4.17}
if [[ "$OPENSHIFT_RELEASE_TYPE" == "ga" ]]; then
    if [[ -z "$OPENSHIFT_VERSION" ]]; then
      error "OPENSHIFT_VERSION is required with OPENSHIFT_RELEASE_TYPE=ga"
      exit 1
    fi
    export OPENSHIFT_RELEASE_STREAM=${OPENSHIFT_VERSION%.*}
fi

if [ "${FIPS_MODE:-false}" = "true" ]; then
    if ! [ "${FIPS_VALIDATE:-false}" = "true" ]; then
        export OPENSHIFT_INSTALL_SKIP_HOSTCRYPT_VALIDATION="true"
    fi
fi

# DNS resolution for amd64.ocp.releases.ci.openshift.org fails
# pretty regularly, so try a few times before giving up.
function get_latest_ci_image() {
    for i in {1..3}; do
        if curl -L https://amd64.ocp.releases.ci.openshift.org/api/v1/releasestream/${OPENSHIFT_RELEASE_STREAM}.0-0.${OPENSHIFT_RELEASE_TYPE}/latest | grep -o 'registry.ci.openshift.org[^"]\+'; then
            return
        fi
        echo "Failed to get CI image" 1>&2
        sleep 2
    done
}

#
# See https://amd64.ocp.releases.ci.openshift.org for release details
#
# if we provide OPENSHIFT_RELEASE_IMAGE, do not curl. This is needed for offline installs
if [ -z "${OPENSHIFT_RELEASE_IMAGE:-}" ]; then
  if [[ "$OPENSHIFT_RELEASE_TYPE" == "ga" ]]; then
    LATEST_CI_IMAGE=$(curl -L https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OPENSHIFT_VERSION}/release.txt  | grep -o 'quay.io/openshift-release-dev/ocp-release[^"]\+')
  else
    LATEST_CI_IMAGE=$(get_latest_ci_image)
    if [ -z "$LATEST_CI_IMAGE" ]; then
      error "No release image found."
      exit 1
    fi
  fi
fi
export OPENSHIFT_RELEASE_IMAGE="${OPENSHIFT_RELEASE_IMAGE:-$LATEST_CI_IMAGE}"
export OPENSHIFT_INSTALL_PATH="${OPENSHIFT_INSTALL_PATH:-$GOPATH/src/github.com/openshift/installer}"

# Override the image to use for installing hive
export HIVE_DEPLOY_IMAGE="${HIVE_DEPLOY_IMAGE:-registry.ci.openshift.org/openshift/hive-v4.0:hive}"

# CI images don't have version numbers
export OPENSHIFT_CI=${OPENSHIFT_CI:-""}
export OPENSHIFT_VERSION=${OPENSHIFT_VERSION:-""}
if [[ -z "$OPENSHIFT_CI" ]]; then
  export OPENSHIFT_VERSION=${OPENSHIFT_VERSION:-$(echo $OPENSHIFT_RELEASE_IMAGE | sed "s/.*:\([[:digit:]]\.[[:digit:]]*\).*/\1/")}
fi

export OPENSHIFT_RELEASE_TAG=$(echo $OPENSHIFT_RELEASE_IMAGE | sed -E 's/[[:alnum:]\/.-]*(release|okd).*://')

# Use "ipmi" for 4.3 as it didn't support redfish, for other versions
# use "redfish", unless its CI where we use "mixed"
if [[ "$OPENSHIFT_VERSION" == "4.3" ]]; then
  export BMC_DRIVER=${BMC_DRIVER:-ipmi}
elif [[ -z "$OPENSHIFT_CI" ]]; then
  export BMC_DRIVER=${BMC_DRIVER:-redfish}
else
  export BMC_DRIVER=${BMC_DRIVER:-mixed}
fi

if [[ "$PROVISIONING_NETWORK_PROFILE" == "Disabled" ]]; then
  export BMC_DRIVER="redfish-virtualmedia"
fi

# Both utils.sh and 04_setup_ironic.sh use this log file, so set the
# name one time. Users should not override this.
export MIRROR_LOG_FILE=${REGISTRY_DIR}/${CLUSTER_NAME}-image_mirror-${OPENSHIFT_RELEASE_TAG}.log

# Switch Container Images to upstream, Installer defaults these to the openshift version
if [ "${UPSTREAM_IRONIC:-false}" != "false" ] ; then
    export IRONIC_LOCAL_IMAGE=${IRONIC_LOCAL_IMAGE:-"quay.io/metal3-io/ironic:main"}
# Starting from Openshift 4.9 the ironic-inspector container is not used anymore
    # FIXME: $OPENSHIFT_VERSION is not defined in CI
    if is_lower_version $OPENSHIFT_VERSION 4.9; then
        export IRONIC_INSPECTOR_LOCAL_IMAGE=${IRONIC_INSPECTOR_LOCAL_IMAGE:-"quay.io/metal3-io/ironic-inspector:master"}
    fi
    export IRONIC_IPA_DOWNLOADER_LOCAL_IMAGE=${IRONIC_IPA_DOWNLOADER_LOCAL_IMAGE:-"quay.io/metal3-io/ironic-ipa-downloader:master"}
    export IRONIC_STATIC_IP_MANAGER_LOCAL_IMAGE=${IRONIC_STATIC_IP_MANAGER_LOCAL_IMAGE:-"quay.io/metal3-io/static-ip-manager"}
    export BAREMETAL_OPERATOR_LOCAL_IMAGE=${BAREMETAL_OPERATOR_LOCAL_IMAGE:-"quay.io/metal3-io/baremetal-operator"}
fi

if [ -z "$KNI_INSTALL_FROM_GIT" ]; then
    export OPENSHIFT_INSTALLER=${OPENSHIFT_INSTALLER:-${OCP_DIR}/openshift-install}
 else
    export OPENSHIFT_INSTALLER=${OPENSHIFT_INSTALLER:-$OPENSHIFT_INSTALL_PATH/bin/openshift-install}

    # This is an URI so we can use curl for either the file on GitHub, or locally
    export OPENSHIFT_INSTALLER_MACHINE_OS=${OPENSHIFT_INSTALLER_MACHINE_OS:-file:///$OPENSHIFT_INSTALL_PATH/data/data/rhcos.json}

    # The installer defaults to origin releases when building from source
    export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="${OPENSHIFT_RELEASE_IMAGE}"
fi

if env | grep -q "_LOCAL_IMAGE=\|_LOCAL_REPO=" ; then
    export MIRROR_IMAGES=true
fi

export LOCAL_IMAGE_URL_SUFFIX="localimages/local-release-image"

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
# Length of DHCP leases
export DHCP_LEASE_EXPIRY=${DHCP_LEASE_EXPIRY:-60}
export LIBVIRT_FIRMWARE=${LIBVIRT_FIRMWARE:-uefi}

FILESYSTEM=${FILESYSTEM:="/"}

export NODES_FILE=${NODES_FILE:-"${WORKING_DIR}/${CLUSTER_NAME}/ironic_nodes.json"}
export EXTRA_NODES_FILE=${EXTRA_NODES_FILE:-"${WORKING_DIR}/${CLUSTER_NAME}/extra_ironic_nodes.json"}
NODES_PLATFORM=${NODES_PLATFORM:-"libvirt"}
BAREMETALHOSTS_FILE=${BAREMETALHOSTS_FILE:-"${OCP_DIR}/baremetalhosts.json"}
EXTRA_BAREMETALHOSTS_FILE=${EXTRA_BAREMETALHOSTS_FILE:-"${OCP_DIR}/extra_baremetalhosts.json"}
export BMO_WATCH_ALL_NAMESPACES=${BMO_WATCH_ALL_NAMESPACES:-"false"}

# Optionally set this to a path to use a local dev copy of
# metal3-dev-env, otherwise it's cloned to $WORKING_DIR
export METAL3_DEV_ENV=${METAL3_DEV_ENV:-}
if [ -z "${METAL3_DEV_ENV}" ]; then
  export METAL3_DEV_ENV_PATH="${WORKING_DIR}/metal3-dev-env"
else
  export METAL3_DEV_ENV_PATH="${METAL3_DEV_ENV}"
fi
export VM_SETUP_PATH="${METAL3_DEV_ENV_PATH}/vm-setup"
export CONTAINER_RUNTIME="podman"

export NUM_MASTERS=${NUM_MASTERS:-"3"}
export NUM_WORKERS=${NUM_WORKERS:-"2"}
export NUM_EXTRA_WORKERS=${NUM_EXTRA_WORKERS:-"0"}
export EXTRA_WORKERS_ONLINE_STATUS=${EXTRA_WORKERS_ONLINE_STATUS:-"true"}
export VM_EXTRADISKS=${VM_EXTRADISKS:-"false"}
export VM_EXTRADISKS_LIST=${VM_EXTRADISKS_LIST:-"vdb"}
export VM_EXTRADISKS_SIZE=${VM_EXTRADISKS_SIZE:-"8G"}
export MASTER_HOSTNAME_FORMAT=${MASTER_HOSTNAME_FORMAT:-"master-%d"}
export WORKER_HOSTNAME_FORMAT=${WORKER_HOSTNAME_FORMAT:-"worker-%d"}

export MASTER_MEMORY=${MASTER_MEMORY:-16384}
export MASTER_DISK=${MASTER_DISK:-50}
export MASTER_VCPU=${MASTER_VCPU:-8}

export WORKER_MEMORY=${WORKER_MEMORY:-8192}
export WORKER_DISK=${WORKER_DISK:-30}
export WORKER_VCPU=${WORKER_VCPU:-4}

export EXTRA_WORKER_MEMORY=${EXTRA_WORKER_MEMORY:-${WORKER_MEMORY}}
export EXTRA_WORKER_DISK=${EXTRA_WORKER_DISK:-${WORKER_DISK}}
export EXTRA_WORKER_VCPU=${EXTRA_WORKER_VCPU:-${WORKER_VCPU}}

# Ironic vars (Image can be use <NAME>_LOCAL_IMAGE to override)
export IRONIC_IMAGE=${IRONIC_IMAGE:-"quay.io/metal3-io/ironic:main"}
export IRONIC_DATA_DIR="${WORKING_DIR}/ironic"
export IRONIC_IMAGES_DIR="${IRONIC_DATA_DIR}/html/images"

# VBMC and Redfish images
export VBMC_IMAGE=${VBMC_IMAGE:-"quay.io/metal3-io/vbmc"}
export SUSHY_TOOLS_IMAGE=${SUSHY_TOOLS_IMAGE:-"quay.io/metal3-io/sushy-tools"}
export VBMC_BASE_PORT=${VBMC_BASE_PORT:-"6230"}
export VBMC_MAX_PORT=$((VBMC_BASE_PORT + NUM_MASTERS + NUM_WORKERS + NUM_EXTRA_WORKERS - 1))
export REDFISH_EMULATOR_IGNORE_BOOT_DEVICE="${REDFISH_EMULATOR_IGNORE_BOOT_DEVICE:-False}"

# Which docker registry image should we use?
export DOCKER_REGISTRY_IMAGE=${DOCKER_REGISTRY_IMAGE:-"quay.io/libpod/registry:2.8"}

export KUBECONFIG="${SCRIPTDIR}/ocp/$CLUSTER_NAME/auth/kubeconfig"

# Use a cloudy ssh that doesn't do Host Key checking
export SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"

# Verify requisites/permissions
# Connect to system libvirt
export LIBVIRT_DEFAULT_URI=qemu:///system

export PULL_SECRET_FILE=${PULL_SECRET_FILE:-$WORKING_DIR/pull_secret.json}

# Ensure a few variables are set, even if empty, to avoid undefined
# variable errors in the next 2 checks.
set +x
export CI_TOKEN=${CI_TOKEN:-}
set -x
export CI_SERVER=${CI_SERVER:-api.ci.l2s4.p1.openshiftapps.com}
export PERSONAL_PULL_SECRET=${PERSONAL_PULL_SECRET:-$SCRIPTDIR/pull_secret.json}

# Ensure working dir is always different than script dir. If not, some
# files may get overriden during deployment process.
if [ "$(realpath ${WORKING_DIR})" == "$(realpath ${SCRIPTDIR})" ]; then
  error "WORKING_DIR must not be the same as SCRIPTDIR, i.e. $(realpath ${WORKING_DIR})"
  error "is used for both. Please change one of them to another directory."
  error "WORKING_DIR will be created automatically if it does not exist."
  exit 1
fi

if [ ! -d "$WORKING_DIR" ]; then
  error "Creating Working Dir"
  sudo mkdir -p "$WORKING_DIR"
  sudo chown "${USER}:${GROUP}" "$WORKING_DIR"
  chmod 755 "$WORKING_DIR"
fi

mkdir -p "$WORKING_DIR/$CLUSTER_NAME"

if [ ! -d "$IRONIC_IMAGES_DIR" ]; then
  error "Creating Ironic Images Dir"
  sudo mkdir -p "$IRONIC_IMAGES_DIR"
fi

# Previously the directory was owned by root, we need to alter
# permissions to be owned by the user running dev-scripts.
if [ ! -f "$IRONIC_IMAGES_DIR/.permissions" ]; then
  error "Resetting permissions on Ironic Images Dir..."
  sudo chown -R "${USER}:${GROUP}" "$IRONIC_DATA_DIR"
  sudo find "$IRONIC_DATA_DIR" -type d -print0 | xargs -0 chmod 755
  sudo chmod -R +r "$IRONIC_DATA_DIR"
  touch "$IRONIC_IMAGES_DIR/.permissions"
fi

# Defaults the variable to enable testing a custom machine-api-operator image
export TEST_CUSTOM_MAO=${TEST_CUSTOM_MAO:-false}

# Set to configure bootstrap VM baremetal network with static IP
# (Currently this just expects a non-empty value, the IP is fixed to .9)
export ENABLE_BOOTSTRAP_STATIC_IP=${ENABLE_BOOTSTRAP_STATIC_IP:-}

# TODO(bnemec): Once https://github.com/ansible/ansible/pull/75537 merges this
# can be removed.
ALMA_PYTHON_OVERRIDE=
source /etc/os-release
export DISTRO="${ID}${VERSION_ID%.*}"
if [[ $DISTRO == "almalinux8" || $DISTRO == "rocky8" ]]; then
    ALMA_PYTHON_OVERRIDE="-e ansible_python_interpreter=/usr/libexec/platform-python"
fi

export ENABLE_LOCAL_REGISTRY=${ENABLE_LOCAL_REGISTRY:-}

# Defaults the DISABLE_MULTICAST variable
export DISABLE_MULTICAST=${DISABLE_MULTICAST:-false}

# Defaults the AGENT_WAIT_FOR_INSTALL_COMPLETE variable
export AGENT_WAIT_FOR_INSTALL_COMPLETE=${AGENT_WAIT_FOR_INSTALL_COMPLETE:-true}

# Agent specific configuration 

function invalidAgentValue() {
  printf "Found invalid value \"$AGENT_E2E_TEST_SCENARIO\" for AGENT_E2E_TEST_SCENARIO. Supported values: 'COMPACT_IPXX', 'HA_IPXX', or 'SNO_IPXX', where XX is 'V4', 'V6', or 'V4V6'"
  exit 1
}

# Agent test scenario
export AGENT_E2E_TEST_SCENARIO=${AGENT_E2E_TEST_SCENARIO:-}
export NETWORKING_MODE=${NETWORKING_MODE:-}
export AGENT_E2E_TEST_BOOT_MODE=${AGENT_E2E_TEST_BOOT_MODE:-"ISO"}

# PXE server port used by agent (when AGENT_E2E_TEST_BOOT_MODE is "PXE")
# Needed to be defined here since it's required also by the shared step 02_configure_host.sh
# to open a firewall port
export AGENT_PXE_SERVER_PORT=${AGENT_PXE_SERVER_PORT:-8089}

# Enable MCE deployment
export AGENT_DEPLOY_MCE=${AGENT_DEPLOY_MCE:-}

if [[ ! -z ${AGENT_E2E_TEST_SCENARIO} ]]; then
  IFS='_'
  read -a arr <<<"$AGENT_E2E_TEST_SCENARIO"
  delimiterCount=$(echo "$AGENT_E2E_TEST_SCENARIO" | tr -cd '_' | wc -c)
  unset IFS

  SCENARIO=${arr[0]}
  export IP_STACK=$(echo ${arr[1]##*IP} | tr V v)
  
  if [[ "$delimiterCount" == "2" ]]; then
    export NETWORKING_MODE=${arr[2]}
    if [[ $NETWORKING_MODE != "DHCP" ]]; then
      invalidAgentValue
    fi
  fi

  case "$SCENARIO" in
      "COMPACT" )
          export NUM_MASTERS=3
          export MASTER_VCPU=4
          export MASTER_DISK=100
          export MASTER_MEMORY=32768
          export NUM_WORKERS=0
          ;;
      "HA" )
          export NUM_MASTERS=3
          export MASTER_VCPU=4
          export MASTER_DISK=100
          export MASTER_MEMORY=32768
          export NUM_WORKERS=2
          export WORKER_VCPU=4
          export WORKER_DISK=100
          export WORKER_MEMORY=9000
          ;;
      "SNO" )
          export NUM_MASTERS=1
          export MASTER_VCPU=8
          export MASTER_DISK=100
          export MASTER_MEMORY=32768
          export NUM_WORKERS=0
          export NETWORK_TYPE="OVNKubernetes"
          export AGENT_PLATFORM_TYPE="${AGENT_PLATFORM_TYPE:-"none"}"
          if [[ "${AGENT_PLATFORM_TYPE}" != "external" ]]  && [[ "${AGENT_PLATFORM_TYPE}" != "none" ]]; then
            echo "Invalid value ${AGENT_PLATFORM_TYPE},  use 'none' or 'external'."
            exit 1
          fi
          ;;
      *)
        invalidAgentValue
  esac

  if [ ! -z "${AGENT_DEPLOY_MCE}" ]; then
    # Assisted service will require at least two local volumes
    export VM_EXTRADISKS=true
    export VM_EXTRADISKS_LIST="vda vdb"
    export VM_EXTRADISKS_SIZE="10G"

    export MASTER_VCPU=8
    export MASTER_MEMORY=32768
  fi

  if [[ $IP_STACK != 'v4' ]] && [[ $IP_STACK != 'v6' ]] && [[ $IP_STACK != 'v4v6' ]]; then
    echo "Invalid value $IP_STACK for IP stack, use 'V4', 'V6', or 'V4V6'."
    exit 1
  fi

  # We're interested in booting a plain iPXE, so setting back the libivirt 
  # firmware to the default 
  if [[ "${AGENT_E2E_TEST_BOOT_MODE}" == "PXE" ]]; then
    LIBVIRT_FIRMWARE=bios
  fi
fi

if [[ ! -z ${AGENT_E2E_TEST_BOOT_MODE} ]]; then
  case "$AGENT_E2E_TEST_BOOT_MODE" in
    "ISO" | "PXE" | "DISKIMAGE")
      # Valid value
      ;;
    *)
      printf "Found invalid value \"$AGENT_E2E_TEST_BOOT_MODE\" for AGENT_E2E_TEST_BOOT_MODE. Supported values: ISO (default), PXE, DISKIMAGE."
      exit 1
      ;;
  esac
fi

if [[ -n "$MIRROR_IMAGES" && "${MIRROR_IMAGES,,}" != "false" ]]; then

   if [[ "${MIRROR_COMMAND}" == "oc-mirror" ]]; then
      # Use the string that is generated by the output of oc-mirror
      export LOCAL_IMAGE_URL_SUFFIX="openshift/release-images"

      # set up the channel using the most recent candidate release
      pushd ${WORKING_DIR}
      release_candidate=`oc-mirror list releases --channel=candidate-${OPENSHIFT_RELEASE_STREAM} | tail -1`
      popd
      export OPENSHIFT_RELEASE_TAG="${release_candidate}-$(uname -m)"
   fi

   # We're going to be using a locally modified release image
   if [[ ! -z ${AGENT_E2E_TEST_SCENARIO} ]]; then
        # For the agent installer version check, a valid tag must be supplied (not 'latest').
       if [[ ${#OPENSHIFT_RELEASE_TAG} = 64 ]] && [[ ${OPENSHIFT_RELEASE_TAG} =~ [:alnum:] ]]; then
         # If the tag is a digest, let's keep the override as OPENSHIFT_RELEASE_IMAGE
         # Since mirror-by-digest-only = true on the bootstrap 
           export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="${OPENSHIFT_RELEASE_IMAGE}"
       else
           export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/${LOCAL_IMAGE_URL_SUFFIX}:${OPENSHIFT_RELEASE_TAG}"
       fi
   else
       # 04_setup_ironic requires tag to be 'latest'
       export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/${LOCAL_IMAGE_URL_SUFFIX}:latest"
   fi
fi

export AGENT_TEST_CASES=${AGENT_TEST_CASES:-}


export PERSISTENT_IMAGEREG=${PERSISTENT_IMAGEREG:-false}
if [ "${OPENSHIFT_CI}" == true ] ; then
  # Disruptive CI tests require a image-registry backed by persistent storage
  export PERSISTENT_IMAGEREG=true
fi
