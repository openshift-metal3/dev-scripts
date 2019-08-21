#!/usr/bin/env bash
set -xe

#
# Build a new installer image
#
# See release_config_example.sh for required configuration steps
#

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
USER=`whoami`

# Get variables from the config file
if [ -z "${RELEASE_CONFIG:-}" ]; then
    # See if there's a release_config_$USER.sh in the SCRIPTDIR
    if [ -f "${SCRIPTDIR}/release_config_${USER}.sh" ]; then
        echo "Using RELEASE_CONFIG ${SCRIPTDIR}/release_config_${USER}.sh"
        RELEASE_CONFIG="${SCRIPTDIR}/release_config_${USER}.sh"
    else
        echo "Please run with a configuration environment set." >&2
        echo "eg RELEASE_CONFIG=release_config_example.sh $0" >&2
        exit 1
    fi
fi
source $RELEASE_CONFIG

INSTALLER_VERSION="$1"
if [ -z "${INSTALLER_VERSION}" ]; then
    echo "usage: $0 <installer version>" >&2
    echo "example: $0 4.0.0-0.9" >&2
    exit 1
fi

echo "Building openshift-installer from ${INSTALLER_GIT_URI}:${INSTALLER_GIT_REF} to ${INSTALLER_STREAM}:${INSTALLER_VERSION}"

# Check prerequisites
if [ $(oc --config "${RELEASE_KUBECONFIG}" project -q) != "${RELEASE_NAMESPACE}" ]; then
    echo "Wrong namespace configured, run 'oc --config ${RELEASE_KUBECONFIG} project ${RELEASE_NAMESPACE}'" >&2
    exit 1
fi

if ! oc --config "${RELEASE_KUBECONFIG}" get imagestream "${INSTALLER_STREAM}" 2>/dev/null; then
    echo "No '${INSTALLER_STREAM}' imagestream in '${RELEASE_NAMESPACE}' namespace" >&2
    exit 1
fi

oc --config "${RELEASE_KUBECONFIG}" apply -f - <<EOF
apiVersion: build.openshift.io/v1
kind: Build
metadata:
  name: openshift-installer-${INSTALLER_VERSION}
spec:
  source:
    type: Git
    git:
      uri: ${INSTALLER_GIT_URI}
      ref: ${INSTALLER_GIT_REF}
  strategy:
    type: Docker
    dockerStrategy:
      imageOptimizationPolicy: SkipLayers
      dockerfilePath: images/baremetal/Dockerfile.ci
  output:
    to:
      kind: ImageStreamTag
      name: ${INSTALLER_STREAM}:${INSTALLER_VERSION}
EOF

BUILD_POD=$(oc --config "${RELEASE_KUBECONFIG}" get build "openshift-installer-${INSTALLER_VERSION}" -o json | jq -r '.metadata.annotations["openshift.io/build.pod-name"]')
oc --config "${RELEASE_KUBECONFIG}" wait --for condition=Ready pod "${BUILD_POD}" --timeout=240s
oc --config "${RELEASE_KUBECONFIG}" logs -f "${BUILD_POD}"

BUILD_PHASE=$(oc --config release-kubeconfig get build "openshift-installer-${INSTALLER_VERSION}" -o json | jq -r .status.phase)
if [ "${BUILD_PHASE}" = "Complete" ]; then
    BUILD_OUTPUT=$(oc --config release-kubeconfig get build "openshift-installer-${INSTALLER_VERSION}" -o json | jq -r .status.output.to.imageDigest)
    echo "Installer built to ${BUILD_OUTPUT}"
else
    echo "Installer build failed? Build phase is ${BUILD_PHASE}"
fi
