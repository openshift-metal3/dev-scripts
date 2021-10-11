#!/usr/bin/bash

metallb_dir="$(dirname $(readlink -f $0))"
source ${metallb_dir}/metallb_common.sh

METALLB_OPERATOR_REPO=${METALLB_OPERATOR_REPO:-"https://github.com/metallb/metallb-operator.git"}
METALLB_OPERATOR_COMMIT=${METALLB_OPERATOR_COMMIT:-"4d52b86"}
LOCAL_REGISTRY_DNS_NAME=${LOCAL_REGISTRY_DNS_NAME:-"virthost.ostest.test.metalkube.org"}
LOCAL_REGISTRY_PORT=${LOCAL_REGISTRY_PORT:-"5000"}
OPERATOR_IMAGE=${OPERATOR_IMAGE:-"${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/metallb-operator:ci"}
METALLB_OPERATOR_DOCKER_FILE=${METALLB_OPERATOR_DOCKER_FILE:-"Dockerfile"}
PERSONAL_PULL_SECRET=${PERSONAL_PULL_SECRET:-"/root/dev-scripts/pull_secret.json"}
PULL_SECRET_FILE=${PULL_SECRET_FILE:-"/opt/dev-scripts/pull_secret.json"}
export NAMESPACE=${NAMESPACE:-"metallb-system"}

if [ ! -d ./metallb-operator ]; then
	git clone ${METALLB_OPERATOR_REPO}
	cd metallb-operator
	git checkout ${METALLB_OPERATOR_COMMIT}
	cd -
fi
cd metallb-operator

podman build . -f ${METALLB_OPERATOR_DOCKER_FILE} -t ${OPERATOR_IMAGE} --authfile ${PERSONAL_PULL_SECRET}
podman push ${OPERATOR_IMAGE} --tls-verify=false --authfile ${PULL_SECRET_FILE}

# install yq v4 for metallb deployment
go install -mod='' github.com/mikefarah/yq/v4@v4.13.3

yq e --inplace '.spec.template.spec.containers[0].env[] |= select (.name=="SPEAKER_IMAGE").value|="'${METALLB_IMAGE_BASE}':'${METALLB_IMAGE_TAG}'"' ${metallb_dir}/metallb-operator-deploy/controller_manager_patch.yaml
yq e --inplace '.spec.template.spec.containers[0].env[] |= select (.name=="CONTROLLER_IMAGE").value|="'${METALLB_IMAGE_BASE}':'${METALLB_IMAGE_TAG}'"' ${metallb_dir}/metallb-operator-deploy/controller_manager_patch.yaml

PATH="${GOPATH}:${PATH}" ENABLE_OPERATOR_WEBHOOK=true KUSTOMIZE_DEPLOY_DIR="../metallb-operator-deploy" IMG=${OPERATOR_IMAGE} make deploy
