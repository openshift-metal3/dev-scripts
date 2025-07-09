#!/usr/bin/env bash

set -ex

source logging.sh
source common.sh
source utils.sh


CAPI_ENABLED_RELEASE=4.19

# If we didn't support CAPI in this release, stop.
if is_lower_version "$(openshift_version "${OCP_DIR}")" "$CAPI_ENABLED_RELEASE"; then
    echo "CAPI is not supported in this openshift version."
    return 0
fi

export FEATURE_SET=TechPreviewNoUpgrade
export BMO_WATCH_ALL_NAMESPACES="true"
export NUM_EXTRA_WORKERS=1
export EXTRA_WORKERS_NAMESPACE="openshift-cluster-api"

./setup_capi_e2e.sh

sync_repo_and_patch cluster-capi-operator https://github.com/openshift/cluster-capi-operator

pushd $REPO_PATH/cluster-capi-operator
make e2e
popd
