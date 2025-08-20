#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing ORAS CLI for bare-metal as a service preparation..."

ansible-playbook -i localhost, -c local "${SCRIPT_DIR}/install-oras.yml"

echo "ORAS CLI installation completed."