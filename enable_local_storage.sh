#!/usr/bin/env bash
set -eux -o pipefail

source logging.sh
source common.sh
source utils.sh

ASSETS_DIR=${ASSETS_DIR:-"${OCP_DIR}/enable-local-storage"}
STORAGE_CLASS_NAME=${STORAGE_CLASS_NAME:-local-storage}


function generate_subscription() {
  mkdir -p "${ASSETS_DIR}"

  cat >"${ASSETS_DIR}/01-local-storage-operator.yaml" <<EOF
apiVersion: operators.coreos.com/v1alpha2
kind: OperatorGroup
metadata:
  name: local-operator-group
  namespace: openshift-local-storage
spec:
  targetNamespaces:
    - openshift-local-storage
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: local-storage-operator
  namespace: openshift-local-storage
spec:
  installPlanApproval: Automatic
  name: local-storage-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
}

function generate_local_volume() {
  mkdir -p "${ASSETS_DIR}"

  cat >"${ASSETS_DIR}/02-local-volume.yaml" <<EOCR
apiVersion: local.storage.openshift.io/v1
kind: LocalVolume
metadata:
  name: ${STORAGE_CLASS_NAME}
  namespace: openshift-local-storage
spec:
  logLevel: Normal
  managementState: Managed
  storageClassDevices:
$(fill_local_storage)
      storageClassName: ${STORAGE_CLASS_NAME}
      volumeMode: Filesystem
EOCR
}


function fill_local_storage() {
  if [ ! -z "${VM_EXTRADISKS_LIST}" ]; then
cat <<EOF
    - devicePaths:
EOF
  fi

  for disk in ${VM_EXTRADISKS_LIST}; do
cat <<EOF
        - /dev/$disk
EOF
  done
}


function deploy_local_storage() {
  oc adm new-project openshift-local-storage || true

  oc annotate --overwrite project openshift-local-storage openshift.io/node-selector=''

if [[ "$OPENSHIFT_RELEASE_TYPE" == "ga" ]]; then
  generate_subscription
  echo "Creating local storage operator group and subscription..."
  oc apply -f "${ASSETS_DIR}/01-local-storage-operator.yaml"
else
  oc project openshift-local-storage
  LSO_PATH=${LOCAL_STORAGE_OPERATOR_PATH:-$GOPATH/src/github.com/openshift/local-storage-operator}
  if [ ! -d $LSO_PATH ]; then
      echo "Did not find $LSO_PATH" 1>&2
      exit 1
  fi
  pushd ${LSO_PATH}
  make build
  # Run make deploy steps manually so we can override the default namespace
  pushd config/manager
  kustomize edit set image controller=controller:latest
  popd
  pushd config/default
  kustomize edit set namespace openshift-local-storage
  popd
  kustomize build config/default | oc apply -f -
  popd
fi
  wait_for_crd "localvolumes.local.storage.openshift.io"

  generate_local_volume
  echo "Creating local volume and storage class..."
  oc apply -f "${ASSETS_DIR}/02-local-volume.yaml"
}


if [ "${VM_EXTRADISKS}" != "false" ]; then
  deploy_local_storage
else
  echo "Cannot deploy local storage unless VM_EXTRADISKS is enabled"
  exit 1
fi
