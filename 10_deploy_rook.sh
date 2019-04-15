#!/usr/bin/bash

set -eux
source logging.sh
source common.sh

figlet "Deploying rook" | lolcat
eval "$(go env)"

export MIXINPATH="$GOPATH/src/github.com/ceph/ceph-mixins"
export ROOKPATH="$GOPATH/src/github.com/rook/rook"
cd $ROOKPATH/cluster/examples/kubernetes/ceph

sed 's/name: rook-ceph$/name: openshift-storage/' common.yaml > common-modified.yaml
sed -i 's/namespace: rook-ceph/namespace: openshift-storage/' common-modified.yaml
oc create -f common-modified.yaml
oc label namespace openshift-storage  "openshift.io/cluster-monitoring=true"
oc policy add-role-to-user view system:serviceaccount:openshift-monitoring:prometheus-k8s -n openshift-storage

sed '/FLEXVOLUME_DIR_PATH/!b;n;c\          value: "\/etc/kubernetes\/kubelet-plugins\/volume\/exec"' operator-openshift.yaml > operator-openshift-modified.yaml
sed -i 's/# - name: FLEXVOLUME_DIR_PATH/- name: FLEXVOLUME_DIR_PATH/' operator-openshift-modified.yaml
sed -i 's/namespace: rook-ceph/namespace: openshift-storage/' operator-openshift-modified.yaml
sed -i 's/:rook-ceph:/:openshift-storage:/' operator-openshift-modified.yaml
oc create -f operator-openshift-modified.yaml
sleep 120

oc wait --for condition=ready  pod -l app=rook-ceph-operator -n openshift-storage --timeout=120s
oc wait --for condition=ready  pod -l app=rook-ceph-agent -n openshift-storage --timeout=120s
oc wait --for condition=ready  pod -l app=rook-discover -n openshift-storage --timeout=120s

sed "s/useAllDevices: .*/useAllDevices: true/" cluster.yaml > cluster-modified.yaml
sed -i 's/# port: 8443/port: 8444/' cluster-modified.yaml
sed -i 's/namespace: rook-ceph/namespace: openshift-storage/' cluster-modified.yaml
oc create -f cluster-modified.yaml
sleep 120

sed 's/namespace: rook-ceph/namespace: openshift-storage/' toolbox.yaml > toolbox-modified.yaml
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

cat <<EOF | oc create -f -
apiVersion: ceph.rook.io/v1
kind: CephFilesystem
metadata:
  name: myfs
  namespace: openshift-storage
spec:
  metadataPool:
    replicated:
      size: 2
  dataPools:
    - replicated:
        size: 2
  metadataServer:
    activeCount: 1
    activeStandby: true
EOF

cd $ROOKPATH/cluster/examples/kubernetes/ceph/monitoring
sed 's/namespace: rook-ceph/namespace: openshift-storage/' service-monitor.yaml > service-monitor-modified.yaml
sed -i 's/- rook-ceph/- openshift-storage/' service-monitor-modified.yaml
oc create -f service-monitor-modified.yaml

cd $MIXINPATH/manifests
oc create -f prometheus-rules.yaml
