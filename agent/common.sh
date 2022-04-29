#!/usr/bin/env bash
set -euxo pipefail

export FLEETING_ISO="${WORKING_DIR}/output/fleeting.iso"
export FLEETING_MANIFESTS_PATH="${WORKING_DIR}/manifests"

export INSTALLER_PR="${INSTALLER_PR:-}"
export FLEETING_STATIC_IP_NODE0_ONLY=${FLEETING_STATIC_IP_NODE0_ONLY:-"false"}
