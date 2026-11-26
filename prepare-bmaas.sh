#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Setting up bare-metal as a service (BMaaS) configuration..."

ansible-playbook -i localhost, -c local "${SCRIPT_DIR}/install-bmaas.yml"

echo "BMaaS setup completed successfully."