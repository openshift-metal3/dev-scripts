#!/usr/bin/bash

figlet "Deploying knative" | lolcat

oc get node | grep -q worker
if [ "$?" != "0" ] ; then
    echo You need workers to properly deploy knative
    echo leaving
    exit 1
fi

git clone https://github.com/openshift-cloud-functions/knative-operators
cd knative-operators/
git fetch --tags
git checkout openshift-v0.4.0
sed -i '/$CMD create ns ${COMPONENT}/a [ "${COMPONENT}" == "knative-eventing"] && oc annotate project ${COMPONENT} node-role.kubernetes.io/worker=' etc/scripts/installation-functions.sh
./etc/scripts/install.sh -q
