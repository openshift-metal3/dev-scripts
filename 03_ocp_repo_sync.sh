#!/bin/bash

set -ex
source logging.sh
source common.sh
source utils.sh

eval "$(go env)"
echo "$GOPATH" | lolcat # should print $HOME/go or something like that
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

# Install operator-sdk for use by the baremetal-operator
sync_repo_and_patch github.com/operator-framework/operator-sdk https://github.com/operator-framework/operator-sdk.git

# Build operator-sdk
pushd "${GOPATH}/src/github.com/operator-framework/operator-sdk"
git checkout master
make dep
make install
popd

# Install baremetal-operator
sync_repo_and_patch github.com/metalkube/baremetal-operator https://github.com/metalkube/baremetal-operator.git
# FIXME(dhellmann): Use the pre-rename version of the operator until
# this repository is ready for the renamed version.
pushd $GOPATH/src/github.com/metalkube/baremetal-operator
git checkout origin/metalkube
popd

# Install rook repository
sync_repo_and_patch github.com/rook/rook https://github.com/rook/rook.git

# Install ceph-mixin repository
sync_repo_and_patch github.com/ceph/ceph-mixins https://github.com/ceph/ceph-mixins.git

# Install web ui operator repository
sync_repo_and_patch github.com/kubevirt/web-ui-operator https://github.com/kubevirt/web-ui-operator
