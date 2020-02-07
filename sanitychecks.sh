#!/bin/bash

function verifyWorkingDirIsWorldReadable {
  if [ ! -d $WORKING_DIR ]; then
    echo "WORKING_DIR ${WORKING_DIR} is not a directory"
    exit 1
  fi

  if [ ! -r $WORKING_DIR ]; then
    echo "Unable to access WORKING_DIR ${WORKING_DIR}"
    exit 1
  fi

  if find "${WORKING_DIR}" -maxdepth 0 ! -perm -o=r | grep . ; then
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

verifyFreeSpace
verifyWorkingDirIsWorldReadable

echo "Sanity checks passed"