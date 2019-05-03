#!/usr/bin/bash

figlet "Deploying knative" | lolcat

found=false
git clone https://github.com/openshift-cloud-functions/knative-operators
cd knative-operators/
git fetch --tags
git checkout openshift-v0.4.0
oc get project | grep -q knative-eventing
if [ "$?" == "0" ] ; then
  oc set resources -n knative-eventing statefulset/controller-manager --limits=memory=1000Mi
  found=true
fi
./etc/scripts/install.sh -q || echo "Please reexecute this script"
[ "$found" = false ] && oc set resources -n knative-eventing statefulset/controller-manager --limits=memory=1000Mi
cat <<EOF | oc apply -f -
apiVersion: admissionregistration.k8s.io/v1beta1
kind: MutatingWebhookConfiguration
metadata:
  name: istio-sidecar-injector
  namespace: istio-system
  labels:
    app: istio-sidecar-injector
    chart: sidecarInjectorWebhook-1.0.6
    release: release-name
    heritage: Tiller
webhooks:
  - name: sidecar-injector.istio.io
    clientConfig:
      service:
        name: istio-sidecar-injector
        namespace: istio-system
        path: "/inject"
      caBundle: ""
    rules:
      - operations: [ "CREATE" ]
        apiGroups: [""]
        apiVersions: ["v1"]
        resources: ["pods"]
    failurePolicy: Fail
    namespaceSelector:
      matchExpressions:
      - key: istio-injection
        operator: NotIn
        values:
        - disabled
EOF
