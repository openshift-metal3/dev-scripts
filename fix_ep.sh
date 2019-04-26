#!/usr/bin/env bash
set -x
set -e

source logging.sh
source utils.sh
source common.sh
source ocp_install_env.sh

# Update kube-system ep/host-etcd used by cluster-kube-apiserver-operator to
# generate storageConfig.urls
patch_ep_host_etcd "$CLUSTER_DOMAIN"
