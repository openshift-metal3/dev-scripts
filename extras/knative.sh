#!/usr/bin/bash


figlet "Deploying knative" | lolcat

oc project default
oc adm policy add-scc-to-user privileged -z default -n default
oc label namespace default istio-injection=enabled
oc adm policy add-scc-to-user anyuid -z istio-ingress-service-account -n istio-system
oc adm policy add-scc-to-user anyuid -z default -n istio-system
oc adm policy add-scc-to-user anyuid -z prometheus -n istio-system
oc adm policy add-scc-to-user anyuid -z istio-egressgateway-service-account -n istio-system
oc adm policy add-scc-to-user anyuid -z istio-citadel-service-account -n istio-system
oc adm policy add-scc-to-user anyuid -z istio-ingressgateway-service-account -n istio-system
oc adm policy add-scc-to-user anyuid -z istio-cleanup-old-ca-service-account -n istio-system
oc adm policy add-scc-to-user anyuid -z istio-mixer-post-install-account -n istio-system
oc adm policy add-scc-to-user anyuid -z istio-mixer-service-account -n istio-system
oc adm policy add-scc-to-user anyuid -z istio-pilot-service-account -n istio-system
oc adm policy add-scc-to-user anyuid -z istio-sidecar-injector-service-account -n istio-system
oc adm policy add-cluster-role-to-user cluster-admin -z istio-galley-service-account -n istio-system
oc adm policy add-scc-to-user anyuid -z cluster-local-gateway-service-account -n istio-system
curl -L https://storage.googleapis.com/knative-releases/serving/latest/istio.yaml | sed 's/LoadBalancer/NodePort/' | oc apply --filename -
oc get cm istio-sidecar-injector -n istio-system -oyaml | sed -e 's/securityContext:/securityContext:\\n      privileged: true/' | sed -e 's/disabled/enabled/' | oc replace -f -
oc delete pod -n istio-system -l istio=sidecar-injector
oc adm policy add-scc-to-user anyuid -z build-controller -n knative-build
oc adm policy add-scc-to-user anyuid -z controller -n knative-serving
oc adm policy add-scc-to-user anyuid -z autoscaler -n knative-serving
oc adm policy add-scc-to-user anyuid -z kube-state-metrics -n knative-monitoring
oc adm policy add-scc-to-user anyuid -z node-exporter -n knative-monitoring
oc adm policy add-scc-to-user anyuid -z prometheus-system -n knative-monitoring
oc adm policy add-cluster-role-to-user cluster-admin -z build-controller -n knative-build
oc adm policy add-cluster-role-to-user cluster-admin -z controller -n knative-serving
curl -L https://storage.googleapis.com/knative-releases/serving/latest/serving.yaml | sed 's/LoadBalancer/NodePort/' | oc apply --filename -
oc apply --filename https://github.com/knative/eventing/releases/download/v0.4.0/release.yaml
oc apply --filename https://github.com/knative/eventing-sources/releases/download/v0.4.0/release.yaml
