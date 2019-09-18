#!/bin/bash

# Derived from https://docs.openshift.com/container-platform/4.1/backup_and_restore/disaster_recovery/scenario-1-infra-recovery.html

set -ex

RUNNING_ETCD_POD=$(oc get pod -n openshift-etcd -l k8s-app=etcd -o  jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' |head -n 1)
RUNNING_ETCD_DNS_NAME=$(oc exec ${RUNNING_ETCD_POD}  -n openshift-etcd  -- /bin/sh -c "cat /run/etcd/environment |grep ETCD_DNS|cut -d'=' -f2")
echo RUNNING_ETCD_POD=${RUNNING_ETCD_POD}
echo RUNNING_ETCD_DNS_NAME=${RUNNING_ETCD_DNS_NAME}

# List existing members
oc exec ${RUNNING_ETCD_POD}  -n openshift-etcd  -- /bin/sh -c "ETCDCTL_API=3 etcdctl --cert /etc/ssl/etcd/system:etcd-peer:${RUNNING_ETCD_DNS_NAME}.crt --key /etc/ssl/etcd/system:etcd-peer:${RUNNING_ETCD_DNS_NAME}.key --cacert /etc/ssl/etcd/ca.crt member list"
#exit 1
STALE_ETCD_POD="etcd-member-master-2"
STALE_ETCD_DNS_NAME="etcd-2.ostest.test.metalkube.org"

#oc exec ${RUNNING_ETCD_POD} -n openshift-etcd  -- /bin/sh -c "ETCDCTL_API=3 etcdctl --cert /etc/ssl/etcd/system:etcd-peer:${RUNNING_ETCD_DNS_NAME}.crt --key /etc/ssl/etcd/system:etcd-peer:${RUNNING_ETCD_DNS_NAME}.key --cacert /etc/ssl/etcd/ca.crt member add  ${STALE_ETCD_POD} --peer-urls=https://${STALE_ETCD_DNS_NAME}:2380"

# Run temporary etcd signer on master-0
KUBE_ETCD_SIGNER_SERVER=$(oc adm release info --image-for kube-etcd-signer-server --registry-config=pull_secret.json)
cat kube-etcd-cert-signer.yaml.template | sed "s!KUBE_ETCD_SIGNER_SERVER!${KUBE_ETCD_SIGNER_SERVER}!" > ocp/kube-etcd-cert-signer.yaml
oc create -f ocp/kube-etcd-cert-signer.yaml

KUBE_CLIENT_AGENT=$(oc adm release info --image-for kube-client-agent --registry-config=pull_secret.json)
SETUP_ETCD_ENVIRONMENT=$(oc adm release info --image-for machine-config-operator --registry-config=pull_secret.json)
STALE_ETCD_POD="etcd-member-master-2"
STALE_ETCD_DNS_NAME="etcd-2.ostest.test.metalkube.org"

# sudo -E /usr/local/bin/etcd-member-recover.sh 192.168.111.20 etcd-member-master-2
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no core@192.168.111.22 "export KUBE_CLIENT_AGENT=$KUBE_CLIENT_AGENT; export SETUP_ETCD_ENVIRONMENT=$SETUP_ETCD_ENVIRONMENT; sudo -E /usr/local/bin/etcd-member-recover.sh 192.168.111.20 etcd-member-master-2"
