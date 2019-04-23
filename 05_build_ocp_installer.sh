#!/bin/bash

set -ex

source logging.sh
source common.sh

figlet "Building the Installer" | lolcat

eval "$(go env)"
echo "$GOPATH" | lolcat # should print $HOME/go or something like that

pushd "$GOPATH/src/github.com/openshift-metal3/kni-installer"
export MODE=release
export TAGS="libvirt ironic"
./hack/build.sh
popd
