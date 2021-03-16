#!/usr/bin/env bash
set -x

source logging.sh
source common.sh
source validation.sh

early_cleanup_validation

sudo podman kill squid
sudo podman rm squid

sudo rm -f squid.conf
