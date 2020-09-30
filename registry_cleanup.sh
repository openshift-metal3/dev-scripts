#!/usr/bin/env bash
set -x

source logging.sh
source common.sh
source validation.sh

early_cleanup_validation

sudo podman kill registry
sudo podman rm registry

sudo rm -rf $WORKING_DIR/registry
