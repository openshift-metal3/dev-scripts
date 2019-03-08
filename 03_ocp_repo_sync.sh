#!/bin/bash

set -ex
source common.sh

eval "$(go env)"
echo "$GOPATH" | lolcat # should print $HOME/go or something like that

function sync_go_repo_and_patch {
    DEST="$GOPATH/src/$1"
    figlet "Syncing $1" | lolcat

    if [ ! -d $DEST ]; then
        mkdir -p $DEST
        git clone $2 $DEST
    fi

    pushd $DEST

    git am --abort || true
    git checkout master
    git pull --rebase origin master
    git branch -D we_dont_need_no_stinkin_patches || true
    git checkout -b we_dont_need_no_stinkin_patches

    shift; shift;
    for arg in "$@"; do
        curl -L $arg | git am
    done
    popd
}

sync_go_repo_and_patch github.com/metalkube/kni-installer https://github.com/metalkube/kni-installer.git

sync_go_repo_and_patch github.com/metalkube/facet https://github.com/metalkube/facet.git

# Build facet
go get -v github.com/rakyll/statik
pushd "${GOPATH}/src/github.com/metalkube/facet"
yarn install
./build.sh
popd

# Install Go dependency management tool
# Using pre-compiled binaries instead of installing from source
curl https://raw.githubusercontent.com/golang/dep/master/install.sh | sh
export PATH="${GOPATH}/bin:$PATH"

# Install operator-sdk for use by the baremetal-operator
sync_go_repo_and_patch github.com/operator-framework/operator-sdk https://github.com/operator-framework/operator-sdk.git

# Build operator-sdk
pushd "${GOPATH}/src/github.com/operator-framework/operator-sdk"
git checkout master
make dep
make install
popd

# Install baremetal-operator
sync_go_repo_and_patch github.com/metalkube/baremetal-operator https://github.com/metalkube/baremetal-operator.git
