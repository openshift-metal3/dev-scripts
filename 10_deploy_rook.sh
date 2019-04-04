#!/usr/bin/bash

set -eux
source logging.sh
source common.sh

figlet "Deploying rook" | lolcat
eval "$(go env)"

export ROOKPATH="$GOPATH/src/github.com/rook/rook"
cd $ROOKPATH/cluster/examples/kubernetes/ceph
oc create -f common.yaml
oc apply -f csi/rbac/rbd/
oc apply -f csi/rbac/cephfs/
wget https://raw.githubusercontent.com/rook/rook/d6b30a2b36eedd8add36a8d4ed61d35e8aedd162/cluster/examples/kubernetes/ceph/operator-openshift-with-csi.yaml
oc create -f operator-openshift-with-csi.yaml || echo Ignoring existing namespace error  
sleep 120
oc wait --for condition=ready  pod -l app=rook-ceph-operator -n rook-ceph --timeout=120s
oc wait --for condition=ready  pod -l app=rook-ceph-agent -n rook-ceph --timeout=120s
oc wait --for condition=ready  pod -l app=rook-discover -n rook-ceph --timeout=120s
sed "s/useAllDevices: .*/useAllDevices: true/" cluster.yaml > cluster-modified.yaml
sed -i 's/# port: 8443/port: 8444/' cluster-modified.yaml
oc create -f cluster-modified.yaml
oc create -f toolbox.yaml
sleep 120
cat <<EOF | oc create -f -
apiVersion: ceph.rook.io/v1
kind: CephBlockPool
metadata:
  name: rbd
  namespace: rook-ceph
spec:
  failureDomain: osd
  replicated:
    size: 2
EOF

KEY=$(pod=$(oc get pod  -n rook-ceph -l app=rook-ceph-operator  -o jsonpath="{.items[0].metadata.name}"); oc exec -n rook-ceph ${pod} -- bash -c "ceph auth get-key client.admin -c /var/lib/rook/rook-ceph/rook-ceph.config | base64")

cat <<EOF | oc create -f -
apiVersion: v1
kind: Secret
metadata:
  name: csi-rbd-secret
  namespace: rook-ceph
data:
  adminID: YWRtaW4=
  monitors: cm9vay1jZXBoLW1vbi1iLnJvb2stY2VwaC5zdmMuY2x1c3Rlci5sb2NhbDo2Nzkw
  admin: $KEY
  adminKey: $KEY
EOF

cat <<EOF | oc create -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: rook-ceph-block
   annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: csi-rbdplugin
parameters:
    monitors: rook-ceph-mon-a.rook-ceph.svc.cluster.local:6789,rook-ceph-mon-b.rook-ceph.svc.cluster.local:6789,rook-ceph-mon-c.rook-ceph.svc.cluster.local:6789
    pool: rbd
    imageFormat: "2"
    imageFeatures: layering
    csiProvisionerSecretName: csi-rbd-secret
    csiProvisionerSecretNamespace: rook-ceph
    csiNodePublishSecretName: csi-rbd-secret
    csiNodePublishSecretNamespace: rook-ceph
    adminid: admin
    userid: admin
    fsType: xfs
reclaimPolicy: Delete
EOF
