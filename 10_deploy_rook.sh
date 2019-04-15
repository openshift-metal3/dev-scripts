#!/usr/bin/bash

set -eux
source logging.sh
source common.sh

figlet "Deploying rook" | lolcat
eval "$(go env)"

export ROOKPATH="$GOPATH/src/github.com/rook/rook"
cd $ROOKPATH/cluster/examples/kubernetes/ceph
oc create -f common.yaml
sed '/FLEXVOLUME_DIR_PATH/!b;n;c\          value: "\/etc/kubernetes\/kubelet-plugins\/volume\/exec"' operator-openshift.yaml > operator-openshift-modified.yaml
sed -i 's/# - name: FLEXVOLUME_DIR_PATH/- name: FLEXVOLUME_DIR_PATH/' operator-openshift-modified.yaml
oc create -f operator-openshift-modified.yaml
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
  clusterNamespace: rook-ceph
  fstype: xfs
reclaimPolicy: Retain
EOF

cat <<EOF | oc create -f -
apiVersion: ceph.rook.io/v1
kind: CephFilesystem
metadata:
  name: myfs
  namespace: rook-ceph
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
