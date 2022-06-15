#!/bin/bash

set -o pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

source $SCRIPTDIR/validation.sh
source $SCRIPTDIR/common.sh

early_deploy_validation

if [[ -z ${AGENT_E2E_TEST_SCENARIO} ]]; then
    echo "AGENT_E2E_TEST_SCENARIO is missing or empty. Did you forget to set the AGENT_E2E_TEST_SCENARIO env var in the config_<USER>.sh file? Supported values: COMPACT_IPV4, COMPACT_IPV6, HA_IPV4, HA_IPV6, SNO_IPV4, SNO_IPV6."
    exit 1
fi
