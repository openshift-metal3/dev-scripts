#!/usr/bin/env bash
set -euxo pipefail

# Ansible collection unit tests
echo "### (UNIT_TEST): Running Ansible collection unit tests"
ansible-test units --local

# Ansible role tests
echo "### (DRY_RUN_TEST): Running Ansible role tests - test run of roles"
ansible-playbook roles/**/tests/*.yml