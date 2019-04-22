#!/usr/bin/env bash
set -xe

#
# Prepare a new release payload based on a supplied payload pullspec
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

RELEASE_PULLSPEC="$1"
if [ -z "${RELEASE_PULLSPEC}" ]; then
    echo "usage: $0 <release pullspec>" >&2
    echo "example: $0 registry.svc.ci.openshift.org/ocp/release:4.0.0-0.9" >&2
    exit 1
fi

# Fetch the release version from payload metadata
RELEASE_VERSION=$(oc adm release info --registry-config "${RELEASE_PULLSECRET}" "${RELEASE_PULLSPEC}" -o json | jq -r .metadata.version)
if [ -z "${RELEASE_VERSION}" -o "${RELEASE_VERSION}" = "null" ]; then
    echo "Could find version metadata in ${RELEASE_PULLSPEC}" >&2
    exit 1
fi

echo "Preparing a release based on version ${RELEASE_VERSION}"

# Check prerequisites
if [ $(oc --config "${RELEASE_KUBECONFIG}" project -q) != "${RELEASE_NAMESPACE}" ]; then
    echo "Wrong namespace configured, run 'oc --config ${RELEASE_KUBECONFIG} project ${RELEASE_NAMESPACE}'" >&2
    exit 1
fi

if ! oc --config "${RELEASE_KUBECONFIG}" get imagestream "${RELEASE_STREAM}" 2>/dev/null; then
    echo "No '${RELEASE_STREAM}' imagestream in '${RELEASE_NAMESPACE}' namespace" >&2
    exit 1
fi

RELEASE_REPO=$(oc --config "${RELEASE_KUBECONFIG}" get imagestream "${RELEASE_STREAM}" -o json | jq -r .status.publicDockerImageRepository)
if [ -z "${RELEASE_REPO}" -o "${RELEASE_REPO}" = "null" ]; then
    echo "No public repository URL found for ${RELEASE_NAMESPACE}/${RELEASE_STREAM}" >&2
    exit 1
fi

RELEASE_TMPDIR=$(mktemp -d "release-${RELEASE_VERSION}-XXXXXXXXXX")
trap "rm -rf ${RELEASE_TMPDIR}" EXIT

# extract image-references
oc adm release extract --registry-config "${RELEASE_PULLSECRET}" --from "${RELEASE_PULLSPEC}" --file image-references > "${RELEASE_TMPDIR}/image-references"

# create new image stream from image-references
oc --config "${RELEASE_KUBECONFIG}" apply -f "${RELEASE_TMPDIR}/image-references"
if ! oc --config "${RELEASE_KUBECONFIG}" get imagestream "${RELEASE_VERSION}" 2>/dev/null; then
    echo "Expected '${RELEASE_VERSION}' imagestream?" >&2
    exit 1
fi

# create the new release payload
oc --config "${RELEASE_KUBECONFIG}" adm release new \
    --registry-config "${RELEASE_PULLSECRET}" \
    --from-image-stream "${RELEASE_VERSION}" \
    --reference-mode source \
    --to-image "${RELEASE_REPO}:${RELEASE_VERSION}"
