#!/usr/bin/env bash
set -x

source logging.sh
source common.sh

sudo podman image prune --all
