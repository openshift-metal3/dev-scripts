#!/usr/bin/bash

set -eux
source logging.sh
source common.sh

figlet "Deploying rook" | lolcat
eval "$(go env)"

export ROOKPATH="$GOPATH/src/github.com/rook/rook"
cd $ROOKPATH/cluster/examples/kubernetes/ceph
oc create -f common.yaml
sed -i '/ROOK_HOSTPATH_REQUIRES_PRIVILEGED/!b;n;c\          value: "true"' operator-openshift.yaml
sed -i '/FLEXVOLUME_DIR_PATH/!b;n;c\          value: "\/etc/kubernetes\/kubelet-plugins\/volume\/exec"' operator-openshift.yaml
sed -i 's/# - name: FLEXVOLUME_DIR_PATH/- name: FLEXVOLUME_DIR_PATH/' operator-openshift.yaml
oc create -f operator-openshift.yaml
oc wait --for condition=ready  pod -l app=rook-ceph-operator -n rook-ceph --timeout=120s
oc wait --for condition=ready  pod -l app=rook-ceph-agent -n rook-ceph --timeout=120s
oc wait --for condition=ready  pod -l app=rook-discover -n rook-ceph --timeout=120s
sed -i "s/useAllDevices: .*/useAllDevices: true/" cluster.yaml
sed -i 's/# port: 8443/port: 8444/' cluster.yaml
oc create -f cluster.yaml
oc create -f toolbox.yaml
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
