#!/usr/bin/env bash

set -xe

source logging.sh
source common.sh

MUST_GATHER_PATH=${MUST_GATHER_PATH:-$LOGDIR/$CLUSTER_NAME/must-gather}
if [ ! -d "$MUST_GATHER_PATH" ]; then
    mkdir -p "$MUST_GATHER_PATH"
fi

if [ ! -z "${MIRROR_IMAGES}" ]; then
  MUST_GATHER_IMAGE="--image=${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/local-release-image:${OPENSHIFT_RELEASE_TAG}-must-gather"
else
  MUST_GATHER_IMAGE=""
fi

oc --insecure-skip-tls-verify adm must-gather $MUST_GATHER_IMAGE --dest-dir "$MUST_GATHER_PATH" > "$MUST_GATHER_PATH/must-gather.log"
