#!/usr/bin/env bash

set -xe

source logging.sh
source common.sh

MUST_GATHER_PATH=${MUST_GATHER_PATH:-$LOGDIR/$CLUSTER_NAME/must-gather}
if [ ! -d "$MUST_GATHER_PATH" ]; then
    mkdir -p "$MUST_GATHER_PATH"
fi

# must-gather doesn't correctly work in disconnected environment, so we
# have to calculcate the pullspec for the image and pass it to oc
if [ -n "${MIRROR_IMAGES}" ]; then
  pullsecret_file=$(mktemp "pullsecret--XXXXXXXXXX")
  echo "${PULL_SECRET}" > "${pullsecret_file}"

  OPENSHIFT_RELEASE_VERSION=$(oc adm release info --registry-config="$pullsecret_file" "$OPENSHIFT_RELEASE_IMAGE" -o json | jq -r ".config.config.Labels.\"io.openshift.release\"")
  MUST_GATHER_IMAGE="--image=${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/local-release-image:${OPENSHIFT_RELEASE_VERSION}-must-gather"
  rm -f "$pullsecret_file"
else
  MUST_GATHER_IMAGE=""
fi

oc --insecure-skip-tls-verify adm must-gather $MUST_GATHER_IMAGE --dest-dir "$MUST_GATHER_PATH" > "$MUST_GATHER_PATH/must-gather.log"
