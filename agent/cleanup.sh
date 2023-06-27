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

case "${AGENT_E2E_TEST_BOOT_MODE}" in
  "PXE" )
    sudo pkill agentpxeserver || true
    rm -rf ${WORKING_DIR}/pxe
    ;;
esac

sudo systemctl stop haproxy || true
sudo rm /etc/haproxy/haproxy.cfg || true
