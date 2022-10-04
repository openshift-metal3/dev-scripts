#!/usr/bin/env bash
set -x

source logging.sh
source common.sh
source validation.sh

early_cleanup_validation

if sudo podman container exists registry; then
  sudo podman kill registry
  sudo podman rm registry
fi

sudo rm -rf $WORKING_DIR/registry
sudo rm -rf $WORKING_DIR/mirror_registry
