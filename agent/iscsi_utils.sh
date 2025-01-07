#!/usr/bin/env bash
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

source $SCRIPTDIR/agent/common.sh

ISCSI_INITIATOR_BASE="iqn.2024-01.ostest.test.metalkube.org"

function agent_add_iscsi_network_to_domain() {
     local domain_name=${1}
     local host_name=${2}
     local index=${3}

     # add the iscsi network
     sudo virt-xml ${domain_name} --add-device --network network=${ISCSI_NETWORK},model=virtio,"boot_order=1"

     # add the hostname binding so that the host can resolve the 'hostname' variable in pxe file
     host_mac=$(sudo virsh domiflist  ${domain_name} | grep ${ISCSI_NETWORK} | awk '{print $5}')
     iscsi_addr=$((20 + $index))
     host_ip="${ISCSI_NETWORK_SUBNET}."${iscsi_addr}
     sudo virsh net-update ${ISCSI_NETWORK} add-last ip-dhcp-host "<host mac='${host_mac}' name='${host_name}' ip='${host_ip}'/>"
}

function agent_create_iscsi_network() {
    sudo virsh net-define /dev/stdin <<EOF
<network>
  <name>${ISCSI_NETWORK}</name>
  <bridge name="virbr2"/>
  <forward/>
  <ip address="${ISCSI_NETWORK_SUBNET}.1" netmask="255.255.255.0">
    <dhcp>
      <range start='${ISCSI_NETWORK_SUBNET}.20' end='${ISCSI_NETWORK_SUBNET}.120'/>
      <bootp file='http://${ISCSI_NETWORK_SUBNET}.1:8089/agent.x86_64-iscsi.ipxe'/>
    </dhcp>
  </ip>
</network>
EOF

    sudo virsh net-start ${ISCSI_NETWORK}
}

function agent_create_iscsi_target() {

    local name=${1}
    local agent_iso=${2}
    local iscsi_disk=${3}

    # create disks
    sudo qemu-img create  -f raw ${iscsi_disk} 120G

    # Create iqn
    sudo targetcli backstores/fileio create name=$name size=120G file_or_dev=${iscsi_disk}

    # Create initiator
    sudo targetcli /iscsi create ${ISCSI_INITIATOR_BASE}:$name

    # Create a lun
    sudo targetcli /iscsi/${ISCSI_INITIATOR_BASE}:$name/tpg1/luns create /backstores/fileio/$name

    # Allow access to initiator
    sudo targetcli /iscsi/${ISCSI_INITIATOR_BASE}:$name/tpg1/acls create ${ISCSI_INITIATOR_BASE}:$name

    # Override iscsi timeout values. Not setting this can result in the error on the target machine:
    #   Unable to recover from DataOut timeout while in ERL=0, closing iSCSI connection
    sudo targetcli /iscsi/${ISCSI_INITIATOR_BASE}:$name/tpg1/acls/${ISCSI_INITIATOR_BASE}:$name set attribute dataout_timeout=60
    sudo targetcli /iscsi/${ISCSI_INITIATOR_BASE}:$name/tpg1/acls/${ISCSI_INITIATOR_BASE}:$name set attribute dataout_timeout_retries=10

    # Save configuration.
    sudo targetcli / saveconfig

    # Copy the ISO to disk
    sudo dd conv=notrunc if=${agent_iso} of=${iscsi_disk} status=progress
}

function agent_create_iscsi_pxe_file() {

    local boot_dir=${1}

    # Set 'hostname' variable in file. It will be resolved by host during PXE boot
    # in order to access a unique target for this host.
cat > "${boot_dir}/agent.x86_64-iscsi.ipxe" << EOF
#!ipxe
set initiator-iqn ${ISCSI_INITIATOR_BASE}:\${hostname}
sanboot --keep iscsi:${ISCSI_NETWORK_SUBNET}.1::::${ISCSI_INITIATOR_BASE}:\${hostname}
EOF
}
