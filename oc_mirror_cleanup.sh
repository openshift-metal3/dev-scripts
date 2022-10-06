#!/usr/bin/env bash
set -euxo pipefail

source common.sh

if [ -d "${WORKING_DIR}/mirror-registry" ]; then
   pushd ${WORKING_DIR}/mirror-registry
   sudo ./mirror-registry uninstall --quayRoot ${WORKING_DIR}/quay-install/ -v --autoApprove
   popd
   rm -rf "${WORKING_DIR}/mirror-registry"
fi

if [[ -f "/usr/local/bin/oc-mirror" ]]; then
  sudo rm "/usr/local/bin/oc-mirror"
fi

if [ -f "${WORKING_DIR}/.oc-mirror.log" ]; then
   rm "${WORKING_DIR}/.oc-mirror.log"
fi

if [ -d "${WORKING_DIR}/oc-mirror-workspace" ]; then
   rm -rf "${WORKING_DIR}/oc-mirror-workspace"
fi

if [ -d "${WORKING_DIR}/quay-install" ]; then
   rm -rf "${WORKING_DIR}/quay-install"
fi

# restore docker config file that was updated with auth settings
if [[ -f ${DOCKER_CONFIG_FILE}.old ]]; then
   cp ${DOCKER_CONFIG_FILE}.old ${DOCKER_CONFIG_FILE}
   rm ${DOCKER_CONFIG_FILE}.old
fi
