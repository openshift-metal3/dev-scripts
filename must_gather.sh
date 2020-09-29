#!/usr/bin/env bash

set -xe

source logging.sh
source common.sh
source utils.sh

MUST_GATHER_PATH=${MUST_GATHER_PATH:-$LOGDIR/$CLUSTER_NAME/must-gather}
if [ ! -d "$MUST_GATHER_PATH" ]; then
    mkdir -p "$MUST_GATHER_PATH"
fi

# must-gather doesn't correctly work in disconnected environment, so we
# have to calculcate the pullspec for the image and pass it to oc
if [ -n "${MIRROR_IMAGES}" ]; then
  write_pull_secret

  OPENSHIFT_RELEASE_VERSION=$(oc adm release info --registry-config="$PULL_SECRET_FILE" "$OPENSHIFT_RELEASE_IMAGE" -o json | jq -r ".config.config.Labels.\"io.openshift.release\"")
  MUST_GATHER_IMAGE="--image=${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/local-release-image:${OPENSHIFT_RELEASE_VERSION}-must-gather"
else
  MUST_GATHER_IMAGE=""
fi

oc --insecure-skip-tls-verify adm must-gather $MUST_GATHER_IMAGE --dest-dir "$MUST_GATHER_PATH" "$@" > "$MUST_GATHER_PATH/must-gather.log"
