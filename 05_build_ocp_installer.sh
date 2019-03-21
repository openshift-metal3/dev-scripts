#!/bin/bash

set -ex

source common.sh

figlet "Building the Installer" | lolcat

eval "$(go env)"
echo "$GOPATH" | lolcat # should print $HOME/go or something like that

pushd "$GOPATH/src/github.com/openshift-metalkube/kni-installer"
export MODE=release
export TAGS="libvirt ironic"
./hack/build.sh
popd
