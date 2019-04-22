#!/usr/bin/bash

CONSUMER_KEY="${CONSUMER_KEY:-}"
CONSUMER_SECRET="${CONSUMER_SECRET:-}"
ACCESS_TOKEN="${ACCESS_TOKEN:-}"
ACCESS_TOKEN_SECRET="${ACCESS_TOKEN_SECRET:-}"

figlet "Deploying tweeting service" | lolcat
if [ -z "$CONSUMER_KEY" ] || [ -z "$CONSUMER_SECRET" ] || [ -z "$ACCESS_TOKEN" ] || [ -z "$ACCESS_TOKEN_SECRET" ] ; then
    echo Missing variables to properly deploy knative tweeter service
    echo "Follow instructions at https://developer.twitter.com/en/docs/basics/authentication/guides/access-tokens.html"
    echo "and set CONSUMER_KEY,CONSUMER_SECRET,ACCESS_TOKEN and ACCESS_TOKEN_SECRET as environment variables"
    exit
fi

git clone https://github.com/markito/ktweeter
cd ktweeter
oc patch configmap/config-network -n knative-serving --type json --patch "$(cat patches/patch_config-network.json)"
oc project dotnet
sed -i "s/namespace: default/namespace: dotnet/" eventing/*
oc apply -f eventing/serviceAccount.yaml
oc adm policy add-scc-to-user privileged -z events-sa
oc apply -f eventing/channel.yaml
oc apply -f eventing/k8sEventSource.yaml
sed "s@dnsName:.*@dnsName: http://http-trigger.default.svc.cluster.local/api/http-trigger@" eventing/subscription.yaml > eventing/subscription-modified.yaml
oc apply -f eventing/subscription-modified.yaml
cat <<EOF | oc create -f -
apiVersion: serving.knative.dev/v1alpha1
kind: Service
metadata:
  name: ktweeter
spec:
  runLatest:
    configuration:
      revisionTemplate:
        spec:
          container:
            env:
            - name: consumer_key
              valueFrom:
                secretKeyRef:
                  key: consumer_key
                  name: twitter.creds
            - name: consumer_secret
              valueFrom:
                secretKeyRef:
                  key: consumer_secret
                  name: twitter.creds
            - name: access_token
              valueFrom:
                secretKeyRef:
                  key: access_token
                  name: twitter.creds
            - name: access_token_secret
              valueFrom:
                secretKeyRef:
                  key: access_token_secret
                  name: twitter.creds
            image: docker.io/bmozaffa/ktweeter:1.0
            livenessProbe:
              failureThreshold: 100
              httpGet:
                path: /api/http-trigger
            readinessProbe:
              failureThreshold: 100
              httpGet:
                path: /api/http-trigger
EOF
cat <<EOF | oc create -f -
apiVersion: v1
kind: Secret
metadata:
  name: twitter.creds
type: Opaque
data:
  consumer_key: $CONSUMER_KEY
  consumer_secret: $CONSUMER_SECRET
  access_token: $ACCESS_TOKEN
  access_token_secret: $ACCESS_TOKEN_SECRET
EOF
