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

if [ -d "${FLEETING_MANIFESTS_PATH}" ]; then
    rm -f ${FLEETING_MANIFESTS_PATH}/*.yaml
fi

if [ -f "${FLEETING_ISO}" ]; then
    rm -f ${FLEETING_ISO}
fi