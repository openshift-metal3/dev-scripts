#!/usr/bin/env bash
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR=${SCRIPTDIR}/logs
source $SCRIPTDIR/logging.sh
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/network.sh
source $SCRIPTDIR/utils.sh
source $SCRIPTDIR/validation.sh
source $SCRIPTDIR/agent/common.sh

early_deploy_validation

function create_image() {
    local asset_dir="${1:-${OCP_DIR}}"
    local openshift_install="$(realpath "${OCP_DIR}/openshift-install")"
    # TODO: replace pushd with --dir argument once nothing in agent
    # installer depends on the working directory
    pushd "${asset_dir}"
    "${openshift_install}" --log-level=debug agent create image
    popd
}

function attach_agent_iso() {
    for (( n=0; n<${2}; n++ ))
    do
        name=${CLUSTER_NAME}_${1}_${n}
        sudo virt-xml ${name} --add-device --disk "${OCP_DIR}/output/agent.iso",device=cdrom,target.dev=sdc
        sudo virt-xml ${name} --edit target=sda --disk="boot_order=1"
        sudo virt-xml ${name} --edit target=sdc --disk="boot_order=2" --start
    done
}

create_image

attach_agent_iso master $NUM_MASTERS
attach_agent_iso worker $NUM_WORKERS


