#!/bin/bash

set -ex

source common.sh

figlet "Building the Installer" | lolcat

eval "$(go env)"
echo "$GOPATH" | lolcat # should print $HOME/go or something like that

pushd "$GOPATH/src/github.com/openshift/installer"
export MODE=dev
./hack/build.sh
popd
