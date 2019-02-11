#!/bin/bash

set -e

source ocp_install_env.sh

sudo podman rm -f ostest-bootstrap || true

rm -rf ocp

sudo rm -rf /etc/NetworkManager/dnsmasq.d/openshift.conf
