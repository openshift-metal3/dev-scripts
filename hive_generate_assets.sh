#!/bin/bash

set -xe

source logging.sh
source common.sh
source utils.sh
source rhcos.sh
source ocp_install_env.sh
source hive_utils.sh

generate_ocp_install_config ${OCP_DIR}
generate_hive_assets ${OCP_DIR}
