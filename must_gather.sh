#!/usr/bin/env bash

set -xeu

source logging.sh
source common.sh
source utils.sh
source network.sh

MUST_GATHER_PATH=${MUST_GATHER_PATH:-$LOGDIR/$CLUSTER_NAME/must-gather-$(date +%F-%H%M%S)}
if [ ! -d "$MUST_GATHER_PATH" ]; then
    mkdir -p "$MUST_GATHER_PATH"
fi

# must-gather doesn't correctly work in disconnected environment, so we
# have to calculcate the pullspec for the image and pass it to oc
if [[ -n "${MIRROR_IMAGES}" && "${MIRROR_IMAGES}" != "false" ]]; then
  write_pull_secret

  MUST_GATHER_RELEASE_IMAGE=$(image_for must-gather | cut -d '@' -f2)
  LOCAL_REGISTRY_PREFIX="${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/${LOCAL_IMAGE_URL_SUFFIX}"
  MUST_GATHER_IMAGE="--image=${LOCAL_REGISTRY_PREFIX}@${MUST_GATHER_RELEASE_IMAGE}"
else
  MUST_GATHER_IMAGE=""
fi

oc --insecure-skip-tls-verify adm must-gather $MUST_GATHER_IMAGE --dest-dir "$MUST_GATHER_PATH" > "$MUST_GATHER_PATH/must-gather.log"

# Gather audit logs
mkdir -p $MUST_GATHER_PATH/audit-logs
oc --insecure-skip-tls-verify adm must-gather $MUST_GATHER_IMAGE --dest-dir "$MUST_GATHER_PATH/audit-logs" -- /usr/bin/gather_audit_logs > "$MUST_GATHER_PATH/audit-logs.log"
