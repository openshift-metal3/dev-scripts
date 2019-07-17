#!/bin/bash

set -ex
source logging.sh
source common.sh
source utils.sh

eval "$(go env)"
echo "GOPATH: $GOPATH" # should print $HOME/go or something like that
# REPO_PATH is used in sync_repo_and_patch from utils.sh
export REPO_PATH="$GOPATH/src"

# Build facet
# FIXME(russellb) - disabled due to build failure related to metal3 rename
#sync_repo_and_patch github.com/openshift-metalkube/facet https://github.com/openshift-metalkube/facet.git
#go get -v github.com/rakyll/statik
#pushd "${GOPATH}/src/github.com/openshift-metalkube/facet"
#yarn install
#./build.sh
#popd

# Install Go dependency management tool
# Using pre-compiled binaries instead of installing from source
mkdir -p $GOPATH/bin
curl https://raw.githubusercontent.com/golang/dep/master/install.sh | sh
export PATH="${GOPATH}/bin:$PATH"

# Install baremetal-operator
sync_repo_and_patch github.com/metal3-io/baremetal-operator https://github.com/metal3-io/baremetal-operator.git
