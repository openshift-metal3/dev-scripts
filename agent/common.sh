#!/usr/bin/env bash
set -euxo pipefail

export FLEETING_PATH=${FLEETING_PATH:-$WORKING_DIR/fleeting}
export FLEETING_ISO=${FLEETING_ISO:-$FLEETING_PATH/output/fleeting.iso}
export FLEETING_MANIFESTS_PATH="${FLEETING_PATH}/manifests"
export FLEETING_PR=${FLEETING_PR:-}
export FLEETING_STATIC_IP_NODE0_ONLY=${FLEETING_STATIC_IP_NODE0_ONLY:-"false"}
