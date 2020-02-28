#!/bin/bash

set -xeu

bindir=$(dirname $0)

MODE=$1
shift

LOGPREFIX_BASE="multicluster-${MODE}-$(date +%F-%H%M%S)"

# Set the log prefix for this process so logging.sh sets up the
# outputs properly. Resetting this later has no effect, because the
# outputs are already redirected.
export LOGPREFIX=${LOGPREFIX_BASE}/

source logging.sh
source utils.sh
source ocp_install_env.sh

MAIN_CONFIG=$1
shift

SECONDARY_CONFIGS="$@"

ALL_CONFIGS="${MAIN_CONFIG} ${SECONDARY_CONFIGS}"

# Load the config and echo the named variable so this script can see
# its value.
function get_var_from_config() {
    export INHERIT_CONFIG=$1
    export VAR_TO_SHOW=$2
    (
        export CONFIG=$INHERIT_CONFIG;
        source common.sh;
        echo ${!VAR_TO_SHOW};
    ) 2>/dev/null
}

function build() {

    # Determine all of the hostnames for the registry so we can
    # configure the certificate properly.
    export ALL_REGISTRY_DNS_NAMES=""
    for config in ${ALL_CONFIGS}; do
        new_name=$(get_var_from_config $config LOCAL_REGISTRY_DNS_NAME)
        ALL_REGISTRY_DNS_NAMES="$ALL_REGISTRY_DNS_NAMES $new_name"
    done

    # Use the first config to set up the registry so we get the right
    # network types, etc.
    CONFIG=${MAIN_CONFIG} make all

    # The LIBVIRT_URI is used by the installer running in a pod in the
    # first cluster, so it must use the IP visible from that
    # cluster. Get the variables needed to build that URL.
    PROVISIONING_HOST_USER=$(get_var_from_config ${MAIN_CONFIG} PROVISIONING_HOST_USER)
    PROVISIONING_HOST_IP=$(get_var_from_config ${MAIN_CONFIG} PROVISIONING_HOST_IP)
    export LIBVIRT_URI=$(build_libvirturi)

    for config in ${SECONDARY_CONFIGS}; do
        export LOGPREFIX="${LOGPREFIX_BASE}/$(basename $config .sh)-"
        CONFIG=$config make hive_assets
    done

    ${bindir}/remove_iptables_isolation_rules.sh
}

function cleanup() {

    for config in ${ALL_CONFIGS}; do
        export LOGPREFIX="${LOGPREFIX_BASE}/"
        CONFIG=$config make clean
    done
}

function usage() {
    echo "ERROR: $1"
    echo "multicluster.sh (build|clean) configfile [configfile...]"
    exit 1
}

case $MODE in
     build)
         build;;
     clean)
         cleanup;;
     *)
         usage "Unknown commnand $MODE";;
esac

echo "Done!" $'\a'
