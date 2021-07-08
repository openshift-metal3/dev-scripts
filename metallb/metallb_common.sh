#!/usr/bin/bash

METALLB_IMAGE_BASE=${METALLB_IMAGE_BASE:-"quay.io/metallb"}
METALLB_IMAGE_TAG=${METALLB_IMAGE_TAG:-"main"}

metallb_dir="$(dirname $(readlink -f $0))"
source ${metallb_dir}/../common.sh
source ${metallb_dir}/../network.sh
