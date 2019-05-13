#!/usr/bin/env bash
set -xe

#
# Build a new cluster operator image
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

OP_NAME="$1"
OP_REPO="$2"
OP_VERSION="$3"
if [ -z "${OP_NAME}" -o -z "${OP_REPO}" -o -z "${OP_VERSION}" ]; then
    echo "usage: $0 <name> <repo> <version tag>" >&2
    echo "example: $0 virt-operator index.docker.io/kubevirt/virt-operator v0.16.3" >&2
    exit 1
fi

echo "Building ${OP_NAME} from ${OP_REPO}:${OP_VERSION} to ${OP_NAME}:${OP_VERSION}"

# Check prerequisites
if [ $(oc --config "${RELEASE_KUBECONFIG}" project -q) != "${RELEASE_NAMESPACE}" ]; then
    echo "Wrong namespace configured, run 'oc --config ${RELEASE_KUBECONFIG} project ${RELEASE_NAMESPACE}'" >&2
    exit 1
fi

if ! oc --config "${RELEASE_KUBECONFIG}" get imagestream "${OP_NAME}" 2>/dev/null; then
    echo "No '${OP_NAME}' imagestream in '${RELEASE_NAMESPACE}' namespace" >&2
    exit 1
fi

# Package up the operator's manifests
OP_TMPDIR=$(mktemp --tmpdir -d "${OP_NAME}-${OP_VERSION}-XXXXXXXXXX")
trap "rm -rf ${OP_TMPDIR}" EXIT

pushd "${SCRIPTDIR}/../clusteroperators/${OP_NAME}"
tar -cvzf "${OP_TMPDIR}/manifests.tar.gz" manifests/
popd

# Append a new layer with the manifests added
oc image append \
    --registry-config "${RELEASE_PULLSECRET}" \
    --from "${OP_REPO}:${OP_VERSION}" \
    --to "registry.svc.ci.openshift.org/${RELEASE_NAMESPACE}/${OP_NAME}:${OP_VERSION}" \
    --image '{"Labels": {"io.openshift.release.operator": "true"} }' \
    "${OP_TMPDIR}/manifests.tar.gz"

echo "New cluster operator available at registry.svc.ci.openshift.org/${RELEASE_NAMESPACE}/${OP_NAME}:${OP_VERSION}"
