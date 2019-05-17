#!/bin/bash

# See docs/release-payload.md for more information

# A namespace and imagestream where the release will be published to
RELEASE_NAMESPACE=kni
RELEASE_STREAM=release

# A kubeconfig for api.ci.openshift.org
RELEASE_KUBECONFIG=release-kubeconfig

# Need access to wherever the payload image - and the
# images referenced by the payload - are hosted
RELEASE_PULLSECRET=release-pullsecret

# The imagestream in $RELEASE_NAMESPACE where kni-installer will be
# published to
INSTALLER_STREAM=installer

# The git repository and ref (e.g. branch) to build kni-installer from
INSTALLER_GIT_URI=https://github.com/openshift-metalkube/kni-installer.git
INSTALLER_GIT_REF=master
