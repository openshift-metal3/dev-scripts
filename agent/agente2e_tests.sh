#!/usr/bin/env bash
set -euxo pipefail

# TODO(lranjbar): Update to podman
# TODO(lranjbar)[AGENT-52]: Add OPENSHIFT_CI values for pull secret and ssh pub key
mkdir -p scratch-test
echo "{'test':'pull-secret'}" > ./scratch-test/pull_secret.json
echo "ssh-rsa TEST user@localhost.localdomain" > ./scratch-test/id_rsa.pub
docker build -f ./agent/images/Dockerfile.agente2e-test --build-arg user=$USER -t agente2e:test .
rm -rf ./scratch-test
docker run -it --rm agente2e:test ./agente2e_test_commands.sh