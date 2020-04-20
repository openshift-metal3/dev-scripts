#!/usr/bin/env bash

source logging.sh
source common.sh

TEST_INFRA_DIR=$WORKING_DIR/test-infra
if ! [ "$NODES_PLATFORM" = "assisted" ]; then
  exit 0
fi


function delete_all() {
    pushd $TEST_INFRA_DIR
    source scripts/assisted_deployment.sh
    destroy_all
    popd
}

delete_all
