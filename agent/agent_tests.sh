#!/usr/bin/env bash
set -euxo pipefail

# TODO(lranjbar)[AGENT-52]: Add OPENSHIFT_CI values for pull secret and ssh pub key
podman build -f ./agent/tests/Dockerfile.agent-test --build-arg user=$USER -t agent:test .
podman run -it --rm agent:test ./agent_test_commands.sh