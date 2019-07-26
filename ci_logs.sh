#!/bin/bash

set -e
SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPTNAME="$(basename ${BASH_SOURCE[0]})"
CI_URL="http://10.8.144.11:8080/job/dev-tools"

if (( $# != 1 )); then
  echo "Usage: ${SCRIPTNAME} <number of CI run>"
  exit 1
fi

if ! curl --fail ${CI_URL}/$1; then
  echo "Error job $1 not found at ${CI_URL}"
  exit 1
fi

LOGDIR="${SCRIPTDIR}/logs/ci/$1"
if [ ! -d  ${LOGDIR} ]; then
  mkdir -p ${LOGDIR}
  pushd ${LOGDIR}
  wget ${CI_URL}/${1}/artifact/logs.tgz
  tar -xvzf logs.tgz
  popd
  echo "Done, see ${LOGDIR}"
else
  echo "Nothing to do, ${LOGDIR} already exists"
fi 
