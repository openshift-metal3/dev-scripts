#!/usr/bin/env bash

CURRENT_CONTEXT=$(kubectl --kubeconfig /etc/kubernetes/kubeconfig config view -o jsonpath='{.current-context}')
CLUSTER_NAME=$(kubectl --kubeconfig /etc/kubernetes/kubeconfig config view -o "jsonpath={.contexts[?(@.name == '""$CURRENT_CONTEXT""')].context.cluster}")
APIURL=$(kubectl --kubeconfig /etc/kubernetes/kubeconfig config view -o "jsonpath={.clusters[?(@.name == '""$CLUSTER_NAME""')].cluster.server}")
APIHOST=$(echo $APIURL | sed -e 's/.*\/\/\([^:]\+\).*/\1/g')
CLUSTER_DOMAIN=${APIHOST#*.}
BASE_DOMAIN=${CLUSTER_DOMAIN#*.}

echo ${!1}
