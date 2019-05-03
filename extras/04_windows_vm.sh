#!/usr/bin/bash

set -eux

figlet "Deploying windows vm" | lolcat


WINDOWS_IMAGE="${WINDOWS_IMAGE:-http://10.8.120.188/Summit2019.raw}"
VM_SIZE="${VM_SIZE:-60}"
VM_MEMORY="${VM_MEMORY:-8192}"

SERVER_IP=$( ip -f inet addr show baremetal |  grep inet | awk '/inet / {print $2}' | cut -d/ -f1)
SERVERS=$(oc get nodes -o jsonpath={.items[*].status.addresses[?\(@.type==\"InternalIP\"\)].address} | xargs)
for server in $SERVERS; do
   ssh -o StrictHostKeyChecking=no core@$server "sudo bash -c 'curl -L https://gist.github.com/karmab/8e8ff7f56499822231505fd2f73107e4/raw/771333117255fb9cb5ef161c3aeff1d5e0a6203f/cnv-bridge > /var/lib/cni/bin/cnv-bridge' ; sudo chmod u+x /var/lib/cni/bin/cnv-bridge"
done

oc project dotnet
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: windows
spec:
  capacity:
    storage: ${VM_SIZE}Gi
  accessModes:
  - ReadWriteMany
  nfs:
    path: /windows
    server: ${SERVER_IP}
  persistentVolumeReclaimPolicy: Recycle
EOF
[ ! -f /windows/disk.img ] && curl ${WINDOWS_IMAGE} > /windows/disk.img
chown 777 /windows/*
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: "windows"
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: ${VM_SIZE}Gi
  volumeName: "windows"
  storageClassName: ""
EOF
cat <<EOF | oc apply -f -
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: brext
spec:
  config: '{
      "cniVersion": "0.3.0",
      "name": "brext",
      "type": "cnv-bridge",
      "bridge": "brext",
      "ipam": {}
    }'
EOF
cat <<EOF | oc apply -f -
apiVersion: kubevirt.io/v1alpha3
kind: VirtualMachine
metadata:
  annotations:
    name.os.template.kubevirt.io/win2k12r2: Microsoft Windows Server 2012 R2
  labels:
    flavor.template.kubevirt.io/large: "true"
    kubevirt.io/os: win2k12r2
    os.template.kubevirt.io/win2k12r2: "true"
    template.kubevirt.ui: openshift_win2k12r2-generic-large
    vm.kubevirt.io/template: win2k12r2-generic-large
    workload.template.kubevirt.io/generic: "true"
    app: windows-app-server
  name: windows-app-server
  namespace: dotnet
spec:
  running: true
  template:
    metadata:
      creationTimestamp: null
      labels:
        vm.kubevirt.io/name: windows-app-server
    spec:
      domain:
        clock:
          timer:
            hpet:
              present: false
            hyperv: {}
            pit:
              tickPolicy: delay
            rtc:
              tickPolicy: catchup
          utc: {}
        devices:
          disks:
          - disk:
              bus: sata
            name: pvcvolume
          interfaces:
          - bridge: {}
            model: e1000
            name: brext
        features:
          acpi: {}
          apic: {}
          hyperv:
            relaxed: {}
            spinlocks:
              spinlocks: 8191
            vapic: {}
        firmware:
          uuid: 5d307ca9-b3ef-428c-8861-06e72d69f223
        machine:
          type: q35
        resources:
          requests:
            memory: ${VM_MEMORY}M
      evictionStrategy: LiveMigrate
      networks:
      - multus:
          networkName: brext
        name: brext
      terminationGracePeriodSeconds: 0
      volumes:
      - name: pvcvolume
        persistentVolumeClaim:
          claimName: windows
EOF
