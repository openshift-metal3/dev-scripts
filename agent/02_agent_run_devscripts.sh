#!/usr/bin/env bash
set -ex

DEVSCRIPTS_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}/.." )" && pwd )"
source $DEVSCRIPTS_SCRIPT_DIR/01_install_requirements.sh
source $DEVSCRIPTS_SCRIPT_DIR/02_configure_host.sh