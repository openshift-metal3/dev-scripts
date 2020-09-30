#!/usr/bin/env bash
set -x

source logging.sh
source common.sh
source validation.sh

early_cleanup_validation

sudo rm -rf $WORKING_DIR
