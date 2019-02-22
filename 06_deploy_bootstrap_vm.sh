#!/usr/bin/env bash
set -x
set -e

source ocp_install_env.sh
source common.sh
source utils.sh

# FIXME this is configuring for the libvirt backend which is dev-only ref
# https://github.com/openshift/installer/blob/master/docs/dev/libvirt-howto.md
# We may need some additional steps from that doc in 02* and also to make the
# qemu endpoint configurable?
if [ ! -d ocp ]; then
    mkdir -p ocp
    cat > ocp/install-config.yaml << EOF
apiVersion: v1beta3
baseDomain: ${BASE_DOMAIN}
metadata:
  name: ${CLUSTER_NAME}
platform:
  libvirt: {}
pullSecret: |
  ${PULL_SECRET}
sshKey: |
  ${SSH_PUB_KEY}
EOF
fi


$GOPATH/src/github.com/openshift/installer/bin/openshift-install --dir ocp --log-level=debug create ignition-configs

# Here we can make any necessary changes to the ignition configs/manifests
# they can later be sync'd back into the installer via a new baremetal target

# Now re create the cluster (using the existing install-config and ignition-configs)
# Since we set the replicas to null, we should only get the bootstrap VM
# FIXME(shardy) this doesn't work, it creates the bootstrap and one master
#$GOPATH/src/github.com/openshift/installer/bin/openshift-install --dir ocp --log-level=debug create cluster
#exit 1

# ... so for now lets create the bootstrap VM manually and use the generated ignition config
# See https://coreos.com/os/docs/latest/booting-with-libvirt.html
IGN_FILE="/var/lib/libvirt/images/${CLUSTER_NAME}-bootstrap.ign"
sudo cp ocp/bootstrap.ign ${IGN_FILE}

export DNS_VIP=$("${PWD}/nthhost" "$EXTERNAL_SUBNET" 2)
# Generate bootstrap mDNS CoreDNS ignition
KEEPALIVED_CONF_TEMPLATE="vrrp_instance API {
    state BACKUP
    interface \${INTERFACE}
    virtual_router_id 51
    priority 50
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass cluster_uuid_api_vip
    }
    virtual_ipaddress {
        \${MASTER_VIP}
    }
}

vrrp_instance DNS {
    state BACKUP
    interface \${INTERFACE}
    virtual_router_id 52
    priority 50
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass cluster_uuid_dns_vip
    }
    virtual_ipaddress {
        ${DNS_VIP}
    }
}
"

MDNS_COREFILE=". {
    errors
    health
    mdns ${CLUSTER_DOMAIN}
    forward . /etc/coredns/resolv.conf
    cache 30
    reload
}
"

MDNS_SERVICE='[Unit]
Description=Serve cluster DNS gathered from mDNS
Wants=network-online.target
After=network-online.target

[Service]
WorkingDirectory=/etc/coredns
ExecStartPre=/bin/sh -c '"'"'grep -v '"${DNS_VIP}"' /etc/resolv.conf | tee /etc/coredns/resolv.conf'"'"'
ExecStartPre=-/usr/bin/podman create \
    --name coredns \
    --volume /etc/coredns:/etc/coredns:z \
    --network host \
    quay.io/metalkube/coredns-mdns \
        --conf /etc/coredns/Corefile
ExecStart=/usr/bin/podman start -a coredns
ExecStop=/usr/bin/podman stop -t 10 coredns

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
'

mkdir -p ignition_patches/generated/bootstrap

cat > ignition_patches/generated/bootstrap/03_coredns.json << EOF
[{"op": "add", "path": "/systemd/units/-", "value": {"contents": "$(sed -E ':a;N;$!ba;s/\\/\\\\/g;s/\r{0,1}\n/\\n/g' <<< "$MDNS_SERVICE")", "enabled": true, "name": "coredns.service"}},{"op": "add", "path": "/storage/files/-", "value": {"filesystem": "root", "path": "/etc/coredns/Corefile", "user": {"name": "root"}, "contents": {"source": "data:text/plain;charset=utf-8;base64,$(base64 -w0 <<< "$MDNS_COREFILE")", "verification": {}}, "mode": 420}},{"op": "add", "path": "/storage/files/-", "value": {"filesystem": "root", "path": "/etc/keepalived/keepalived.conf.template", "user": {"name": "root"}, "contents": {"source": "data:text/plain;charset=utf-8;base64,$(base64 -w0 <<< "$KEEPALIVED_CONF_TEMPLATE")", "verification": {}}, "mode": 420}},{"op": "add", "path": "/storage/files/-", "value": {"filesystem": "root", "path": "/etc/dhcp/dhclient.conf", "user": {"name": "root"}, "contents": {"source": "data:text/plain;charset=utf-8;base64,$(base64 -w0 <<< "prepend domain-name-servers ${DNS_VIP};")", "verification": {}}, "mode": 420}}]
EOF

# Apply patches to bootstrap ignition
apply_ignition_patches bootstrap "$IGN_FILE"

LATEST_IMAGE=$(ls -ltr redhat-coreos-maipo-*-qemu.qcow2 | tail -n1 | awk '{print $9}')
sudo cp $LATEST_IMAGE /var/lib/libvirt/images/${CLUSTER_NAME}-bootstrap.qcow2
sudo virt-install --connect qemu:///system \
             --import \
             --name ${CLUSTER_NAME}-bootstrap \
             --ram 4096 --vcpus 4 \
             --os-type=linux \
             --os-variant=virtio26 \
             --disk path=/var/lib/libvirt/images/${CLUSTER_NAME}-bootstrap.qcow2,format=qcow2,bus=virtio \
             --vnc --noautoconsole \
             --network bridge=baremetal --network bridge=provisioning \
             --print-xml > ocp/bootstrap-vm.xml
sed -i 's|type="kvm"|type="kvm" xmlns:qemu="http://libvirt.org/schemas/domain/qemu/1.0"|' ocp/bootstrap-vm.xml
sed -i "/<\/devices>/a <qemu:commandline>\n  <qemu:arg value='-fw_cfg'/>\n  <qemu:arg value='name=opt/com.coreos/config,file=${IGN_FILE}'/>\n</qemu:commandline>" ocp/bootstrap-vm.xml
sudo virsh define ocp/bootstrap-vm.xml
sudo virsh start ${CLUSTER_NAME}-bootstrap
sleep 10

while ! domain_net_ip ${CLUSTER_NAME}-bootstrap baremetal; do
  echo "Waiting for ${CLUSTER_NAME}-bootstrap interface to become active.."
  sleep 10
done

# NOTE: This is equivalent to the external API DNS record pointing the API to the API VIP
IP=$(domain_net_ip ${CLUSTER_NAME}-bootstrap baremetal)
export API_VIP=$(dig +noall +answer "api.${CLUSTER_DOMAIN}" @$(network_ip baremetal) | awk '{print $NF}')
echo "address=/api.${CLUSTER_DOMAIN}/${API_VIP}" | sudo tee /etc/NetworkManager/dnsmasq.d/openshift.conf
sudo systemctl reload NetworkManager

# Wait for ssh to start
while ! ssh -o "StrictHostKeyChecking=no" core@$IP id ; do sleep 5 ; done

# Create a master_nodes.json file
jq '.nodes[0:3] | {nodes: .}' "${NODES_FILE}" | tee "${MASTER_NODES_FILE}"

MASTER_INTERFACE="eth1"

# Fix etcd discovery on bootstrap
rm -rf ocp/machineconfigs
mkdir -p ocp/machineconfigs/temp
# Find master machine config name
while [ -z $(ssh -o StrictHostKeyChecking=no "core@$IP" sudo ls /etc/mcs/bootstrap/machine-configs/master*) ]; do sleep 5; done

MASTER_CONFIG=$(ssh -o StrictHostKeyChecking=no "core@$IP" sudo ls /etc/mcs/bootstrap/machine-configs/master*)
ssh -o "StrictHostKeyChecking=no" "core@$IP" sudo cat "${MASTER_CONFIG}" > ocp/machineconfigs/temp/master.yaml
# Extract etcd-member.yaml part
yq -r ".spec.config.storage.files[] | select(.path==\"/etc/kubernetes/manifests/etcd-member.yaml\") | .contents.source" ocp/machineconfigs/temp/master.yaml | sed 's;data:,;;' > ocp/machineconfigs/temp/etcd-member.urlencode
# URL decode
cat ocp/machineconfigs/temp/etcd-member.urlencode | urldecode > ocp/machineconfigs/etcd-member.yaml
# Add a new param to args in discovery container
sed -i "s;- \"run\";- \"run\"\\n    - \"--if-name=${MASTER_INTERFACE}\";g" ocp/machineconfigs/etcd-member.yaml
# URL encode yaml
cat ocp/machineconfigs/etcd-member.yaml | jq -sRr @uri > ocp/machineconfigs/temp/etcd-member.urlencode_updated
# Replace etcd-member contents in the yaml
sed "s;$(cat ocp/machineconfigs/temp/etcd-member.urlencode);$(cat ocp/machineconfigs/temp/etcd-member.urlencode_updated);g" ocp/machineconfigs/temp/master.yaml > ocp/machineconfigs/master.yaml
# Copy the changed file back to bootstrap
cat ocp/machineconfigs/master.yaml | ssh -o "StrictHostKeyChecking=no" "core@$IP" sudo dd of="${MASTER_CONFIG}"

# Generate "dynamic" ignition patches
machineconfig_generate_patches "master"
# Apply patches to masters
patch_node_ignition "master" "$IP"

echo "You can now ssh to \"$IP\" as the core user"
