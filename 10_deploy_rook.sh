#!/usr/bin/bash

set -eux
source logging.sh
source common.sh

figlet "Deploying rook" | lolcat
eval "$(go env)"

CEPH_VERSION="v14.2.0-20190410"
ROOK_VERSION="v0.9.0-465.g5f6de03"
GIT_VERSION="5f6de03d47539c1c3d262551d0122f6c3866cb05"
export MIXINPATH="$GOPATH/src/github.com/ceph/ceph-mixins"
export ROOKPATH="$GOPATH/src/github.com/rook/rook"
cd $ROOKPATH/cluster/examples/kubernetes/ceph
git checkout $GIT_VERSION

sed 's/name: rook-ceph$/name: openshift-storage/' common.yaml > common-modified.yaml
sed -i 's/namespace: rook-ceph/namespace: openshift-storage/' common-modified.yaml
oc create -f common-modified.yaml
oc label namespace openshift-storage  "openshift.io/cluster-monitoring=true"
oc policy add-role-to-user view system:serviceaccount:openshift-monitoring:prometheus-k8s -n openshift-storage

sed 's/namespace: rook-ceph/namespace: openshift-storage/' operator-openshift.yaml > operator-openshift-modified.yaml
sed -i 's/:rook-ceph:/:openshift-storage:/' operator-openshift-modified.yaml
sed -i "s@rook/ceph:master@rook/ceph:$ROOK_VERSION@" operator-openshift-modified.yaml
oc create -f operator-openshift-modified.yaml
sleep 120

oc wait --for condition=ready  pod -l app=rook-ceph-operator -n openshift-storage --timeout=120s
oc wait --for condition=ready  pod -l app=rook-ceph-agent -n openshift-storage --timeout=120s
oc wait --for condition=ready  pod -l app=rook-discover -n openshift-storage --timeout=120s

sed "s/useAllDevices: .*/useAllDevices: true/" cluster.yaml > cluster-modified.yaml
sed -i 's/# port: 8443/port: 8444/' cluster-modified.yaml
sed -i 's/namespace: rook-ceph/namespace: openshift-storage/' cluster-modified.yaml
sed -i 's/allowUnsupported: false/allowUnsupported: true/' cluster-modified.yaml
sed -i "s@image: ceph/ceph.*@image: ceph/ceph:$CEPH_VERSION@" cluster-modified.yaml
oc create -f cluster-modified.yaml
sleep 120

sed 's/namespace: rook-ceph/namespace: openshift-storage/' toolbox.yaml > toolbox-modified.yaml
sed -i "s@rook/ceph:master@rook/ceph:$ROOK_VERSION@" toolbox-modified.yaml
oc create -f toolbox-modified.yaml

cat <<EOF | oc create -f -
apiVersion: ceph.rook.io/v1
kind: CephBlockPool
metadata:
  name: rbd
  namespace: openshift-storage
spec:
  failureDomain: osd
  replicated:
    size: 2
EOF

cat <<EOF | oc create -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: rook-ceph-block
   annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ceph.rook.io/block
parameters:
  blockPool: rbd
  clusterNamespace: openshift-storage
  fstype: xfs
reclaimPolicy: Retain
EOF

cd $ROOKPATH/cluster/examples/kubernetes/ceph/monitoring
sed 's/namespace: rook-ceph/namespace: openshift-storage/' service-monitor.yaml > service-monitor-modified.yaml
sed -i 's/- rook-ceph/- openshift-storage/' service-monitor-modified.yaml
sed -i 's/rook_cluster: rook-ceph/rook_cluster: openshift-storage/' service-monitor-modified.yaml
sed -i 's/interval: 5s/interval: 2s/' service-monitor-modified.yaml
oc create -f service-monitor-modified.yaml

cd $MIXINPATH/manifests
oc create -f prometheus-rules.yaml
