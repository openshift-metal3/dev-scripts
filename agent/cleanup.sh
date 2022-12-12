#!/usr/bin/env bash
set -x

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOGDIR=${SCRIPTDIR}/logs
source $SCRIPTDIR/logging.sh
source $SCRIPTDIR/common.sh
source $SCRIPTDIR/utils.sh
source $SCRIPTDIR/validation.sh
source $SCRIPTDIR/agent/common.sh

early_cleanup_validation

rm -rf "${OCP_DIR}/manifests"
rm -rf "${OCP_DIR}/output"

for host in $(cat "${OCP_DIR}"/hostname); 
do
    sudo sed -i "/${host}/d" /etc/hosts
done
