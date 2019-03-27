#!/usr/bin/bash

set -eux
source common.sh

figlet "Deploying rook" | lolcat
eval "$(go env)"

export ROOKPATH="$GOPATH/src/github.com/rook/rook"
cd $ROOKPATH/cluster/examples/kubernetes/ceph
oc create namespace rook-ceph-system
oc create configmap csi-cephfs-config -n rook-ceph-system --from-file=csi/template/cephfs
oc create configmap csi-rbd-config -n rook-ceph-system --from-file=csi/template/rbd
oc apply -f csi/rbac/rbd
oc apply -f csi/rbac/cephfs
sed -i '/ROOK_HOSTPATH_REQUIRES_PRIVILEGED/!b;n;c\          value: "true"' operator-with-csi.yaml
sed -i '/FLEXVOLUME_DIR_PATH/!b;n;c\          value: "\/etc/kubernetes\/kubelet-plugins\/volume\/exec"' operator-with-csi.yaml
sed -i 's/# - name: FLEXVOLUME_DIR_PATH/- name: FLEXVOLUME_DIR_PATH/' operator-with-csi.yaml
oc create -f scc.yaml
oc adm policy add-scc-to-user privileged -z rook-csi-rbd-provisioner-sa -n rook-ceph-system
oc adm policy add-scc-to-user privileged -z rook-csi-rbd-attacher-sa -n rook-ceph-system
oc adm policy add-scc-to-user privileged -z rook-csi-rbd-plugin-sa -n rook-ceph-system
oc adm policy add-scc-to-user privileged -z rook-csi-cephfs-plugin-sa -n rook-ceph-system
oc adm policy add-scc-to-user privileged -z rook-csi-cephfs-provisioner-sa -n rook-ceph-system
oc create -f operator-with-csi.yaml || echo Ignoring ignoring error about allready existing namespace rook-ceph-system
oc wait --for condition=ready  pod -l app=rook-ceph-operator -n rook-ceph-system --timeout=120s
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
    size: 3
EOF

# k8s1.12
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

# k8s1.13
#sleep 240
#KEY=$(pod=$(oc get pod  -n rook-ceph-system -l app=rook-ceph-operator  -o jsonpath="{.items[0].metadata.name}"); oc exec -n rook-ceph-system ${pod} -- bash -c "ceph auth get-key client.admin -c /var/lib/rook/rook-ceph/rook-ceph.config | base64")
#
#cat <<EOF | oc create -f -
#apiVersion: v1
#kind: Secret
#metadata:
#  name: csi-rbd-secret
#  namespace: default
#data:
#  adminID: YWRtaW4=
#  monitors: cm9vay1jZXBoLW1vbi1iLnJvb2stY2VwaC5zdmMuY2x1c3Rlci5sb2NhbDo2Nzkw
#  admin: $KEY
#  adminKey: $KEY
#EOF
#
#cat <<EOF | oc create -f -
#apiVersion: storage.k8s.io/v1
#kind: StorageClass
#metadata:
#   name: csi-rbd
#   annotations:
#    storageclass.kubernetes.io/is-default-class: "true"
#provisioner: csi-rbdplugin
#parameters:
#    monitors: rook-ceph-mon-a.rook-ceph.svc.cluster.local:6789,rook-ceph-mon-b.rook-ceph.svc.cluster.local:6789,rook-ceph-mon-c.rook-ceph.svc.cluster.local:6789
#    pool: rbd
#    imageFormat: "2"
#    imageFeatures: layering
#    csiProvisionerSecretName: csi-rbd-secret
#    csiProvisionerSecretNamespace: default
#    csiNodePublishSecretName: csi-rbd-secret
#    csiNodePublishSecretNamespace: default
#    adminid: admin
#    userid: admin
#    fsType: xfs
#    multiNodeWritable: "enabled"
#reclaimPolicy: Delete
#EOF
