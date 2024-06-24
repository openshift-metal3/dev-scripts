#!/bin/bash

set -ex

source logging.sh
source common.sh
source utils.sh

# The variable used by "make deploy" below is set here so we can
# change it if we need to mirror the image.
export DEPLOY_IMAGE="${HIVE_DEPLOY_IMAGE}"

if [[ ! -z "${MIRROR_IMAGES}" && "${MIRROR_IMAGES}" != "false" ]]; then
    # Mirror hive itself
    DEPLOY_IMAGE="${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/hive:latest"
    oc image mirror \
       -a ${REGISTRY_CREDS} \
       ${HIVE_DEPLOY_IMAGE} \
       ${DEPLOY_IMAGE}
fi

# Check out hive and install it. This has to be done in the GOPATH
# location because the installation uses 'go run' which needs to
# compile the command it is using.
if [[ ! -d $GOPATH/src/github.com/openshift/hive ]]; then
    sync_repo_and_patch go/src/github.com/openshift/hive https://github.com/openshift/hive.git
fi
pushd $HOME/go/src/github.com/openshift/hive

make deploy

# Installing launches an operator, which can take a little while to be
# all the way up. We need to modify it's config resource, so we watch
# for it to be created before continuing.
while ! oc get hiveconfig hive -n hive 2>/dev/null 1>&2; do
    echo "Waiting for hiveconfig to be ready..."
    sleep 10
done

# Disable log collection because it requires persistent storage, which
# a dev-scripts cluster does not have by default.
oc patch hiveconfig hive -n hive --type=merge \
   --patch="
spec:
  failedProvisionConfig:
    skipGatherLogs: true
"

oc get hiveconfig hive -n hive -o yaml
