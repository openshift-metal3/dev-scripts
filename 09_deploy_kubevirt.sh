#!/usr/bin/bash

UIVERSION="${UIVERSION:-v2.0.0-13.1}"
set -eux
source common.sh

source logging.sh

figlet "Deploying kubevirt" | lolcat
eval "$(go env)"


# FIXME - what are the prerequisites we need to wait for here, is waiting for 
# bootstrap complete enough?

# These will ultimately be deployed via kni-installer to the bootstrap node
# where they will then be applied to the cluster, but for now we do it
# manually
export CURRENT_PROJECT=$(oc project -q)
trap "oc project ${CURRENT_PROJECT}" EXIT
cd manifests
for manifest in $(ls -1 *.yaml | sort -h); do
  oc --as system:admin --config ../ocp/auth/kubeconfig apply -f ${manifest}
  echo "manifests/${manifest} applied"
done

export UIPATH="$GOPATH/src/github.com/kubevirt/web-ui-operator"

oc new-project kubevirt-web-ui
cd $UIPATH/deploy
oc apply -f service_account.yaml
oc adm policy add-scc-to-user anyuid -z kubevirt-web-ui-operator
oc adm policy add-cluster-role-to-user cluster-admin system:serviceaccount:kubevirt-web-ui:kubevirt-web-ui-operator
oc apply -f role.yaml
oc apply -f role_binding.yaml
oc apply -f crds/kubevirt_v1alpha1_kwebui_crd.yaml
oc apply -f operator.yaml
sed "s/okdvirt/openshiftvirt/" crds/kubevirt_v1alpha1_kwebui_cr.yaml > crds/kubevirt_v1alpha1_kwebui_cr-modified.yaml
sed -i "s/version: .*/version: \"$UIVERSION\"/" crds/kubevirt_v1alpha1_kwebui_cr-modified.yaml
oc apply -f crds/kubevirt_v1alpha1_kwebui_cr-modified.yaml
