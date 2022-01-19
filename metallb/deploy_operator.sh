#!/usr/bin/bash

metallb_dir="$(dirname $(readlink -f $0))"
source ${metallb_dir}/metallb_common.sh

METALLB_OPERATOR_REPO=${METALLB_OPERATOR_REPO:-"https://github.com/metallb/metallb-operator.git"}
METALLB_OPERATOR_COMMIT=${METALLB_OPERATOR_COMMIT:-"4d52b86"}
METALLB_OPERATOR_IMAGE_TAG=${METALLB_OPERATOR_IMAGE_TAG:-"metallb-operator"}
export NAMESPACE=${NAMESPACE:-"metallb-system"}

if [ ! -d ./metallb-operator ]; then
	git clone ${METALLB_OPERATOR_REPO}
	cd metallb-operator
	git checkout ${METALLB_OPERATOR_COMMIT}
	cd -
fi
cd metallb-operator

# install yq v4 for metallb deployment
go install -mod='' github.com/mikefarah/yq/v4@v4.13.3

yq e --inplace '.spec.template.spec.containers[0].env[] |= select (.name=="SPEAKER_IMAGE").value|="'${METALLB_IMAGE_BASE}':'${METALLB_IMAGE_TAG}'"' ${metallb_dir}/metallb-operator-deploy/controller_manager_patch.yaml
yq e --inplace '.spec.template.spec.containers[0].env[] |= select (.name=="CONTROLLER_IMAGE").value|="'${METALLB_IMAGE_BASE}':'${METALLB_IMAGE_TAG}'"' ${metallb_dir}/metallb-operator-deploy/controller_manager_patch.yaml
yq e --inplace '.spec.template.spec.containers[0].env[] |= select (.name=="FRR_IMAGE").value|="'${METALLB_IMAGE_BASE}':'${FRR_IMAGE_TAG}'"' ${metallb_dir}/metallb-operator-deploy/controller_manager_patch.yaml

PATH="${GOPATH}:${PATH}" ENABLE_OPERATOR_WEBHOOK=true KUSTOMIZE_DEPLOY_DIR="../metallb-operator-deploy" IMG="${METALLB_IMAGE_BASE}:${METALLB_OPERATOR_IMAGE_TAG}" make deploy
