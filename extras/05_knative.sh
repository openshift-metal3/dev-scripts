#!/usr/bin/bash

figlet "Deploying knative" | lolcat

git clone https://github.com/openshift-cloud-functions/knative-operators
cd knative-operators/
git fetch --tags
git checkout openshift-v0.4.0
./etc/scripts/install.sh -q
