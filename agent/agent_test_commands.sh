#!/usr/bin/env bash
set -euxo pipefail

# Ansible collection unit tests
echo "### (UNIT_TEST): Running Ansible collection unit tests"
ansible-test units -v
