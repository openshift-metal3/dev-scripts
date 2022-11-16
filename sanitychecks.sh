#!/bin/bash

set -euxo pipefail

# The minimum amount of space required for a default installation, expressed in GB
MIN_SPACE_REQUIRED=${MIN_SPACE_REQUIRED:=80}

function verifyClean {
    if [ -d "ocp/${CLUSTER_NAME}" ]; then
      echo "A cluster named '${CLUSTER_NAME}' already exists on this host. Run 'make clean' to remove it before doing another deployment."
      exit 1
    fi
}

function verifyWorkingDir {
  if [ ! -d $WORKING_DIR ]; then
    echo "WORKING_DIR ${WORKING_DIR} is not a directory"
    exit 1
  fi

  if [ ! -r $WORKING_DIR -o ! -w $WORKING_DIR ]; then
    echo "Unable to access WORKING_DIR ${WORKING_DIR}"
    exit 1
  fi

  if ! sudo -u nobody test -r ${WORKING_DIR}; then
    echo "The WORKING_DIR ${WORKING_DIR} is not world-readable!"
    exit 1 
  fi
}

function verifyFreeSpace {
  AVAIL=$(df -h --output=avail -B 1G $WORKING_DIR | tail -n 1)

  if (( $AVAIL < $MIN_SPACE_REQUIRED )); then 
    echo "Not enough free space, at least MIN_SPACE_REQUIRED=${MIN_SPACE_REQUIRED} GB required"
    exit 1
  fi
}

verifyClean
verifyWorkingDir
verifyFreeSpace

echo "Sanity checks passed"
