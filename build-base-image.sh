#!/bin/bash

set -euxo pipefail

BASE_IMAGE_DIR=${1:-base-image}
CUSTOM_REPO_FILE=${2:-custom.repo}

REPO_FILE_PATH="${BASE_IMAGE_DIR}/${CUSTOM_REPO_FILE}"

[ ! -f "${REPO_FILE_PATH}" ] && { echo "${REPO_FILE_PATH} does not exist!"; exit 1; }
[ ! -s "${REPO_FILE_PATH}" ] && { echo "WARNING! ${REPO_FILE_PATH} is empty!"; }

BUILD_COMMAND_ARGS="--build-arg TEST_REPO=${CUSTOM_REPO_FILE}"

# we can change the image used to build the base-image setting the BASE_IMAGE_FROM variable
# in the config file, for example export BASE_IMAGE_FROM=centos:8
if [[ -n ${BASE_IMAGE_FROM:-} ]]; then
    BUILD_COMMAND_ARGS+=" --build-arg BASE_IMAGE_FROM=${BASE_IMAGE_FROM}"
    BUILD_COMMAND_ARGS+=" --build-arg REMOVE_OLD_REPOS=no"
fi

sudo podman build --tag ${BASE_IMAGE_DIR} ${BUILD_COMMAND_ARGS} -f "${BASE_IMAGE_DIR}/Dockerfile"
