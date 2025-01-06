#!/usr/bin/env bash
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

source $SCRIPTDIR/agent/common.sh

function agent_add_iscsi_network_to_domain() {
     local domain_name=${1}

     # add the iscsi network
     sudo virt-xml ${domain_name} --add-device --network network=${ISCSI_NETWORK},model=virtio,"boot_order=1"

     # In order to boot from the iscsi network any other the
     # boot configurations must be removed from the domain
     # TODO - need to check if these exist before removing
     # sudo virt-xml ${domain_name} --remove-device --disk device=cdrom,target.dev=sdc
     # sudo virt-xml ${domain_name} --remove-device --disk device=disk,target.dev=sda

     # set to boot from network
     # Note - this should not be needed if boot_order is set for the iscsi network
     # sudo virt-xml --edit --boot network ${domain_name}
}

function agent_create_iscsi_network() {
    # TODO find macs and substitute them
    #  <host mac='52:54:00:a0:08:c6' name='ostest-worker-0' ip='192.168.145.20'/>
    #  <host mac='52:54:00:9e:f8:b3' name='ostest-worker-1' ip='192.168.145.21'/>
    # TODO - remove hardcoded IP
    cat <<EOF
<network>
  <name>${ISCSI_NETWORK}</name>
  <bridge name="virbr2"/>
  <forward/>
  <ip address="192.168.145.1" netmask="255.255.255.0">
    <dhcp>
      <range start='192.168.145.20' end='192.168.145.120'/>
      <bootp file='http://192.168.145.1:8089/agent.x86_64-iscsi.ipxe'/>
    </dhcp>
  </ip>
</network>
EOF

}

function agent_create_iscsi_target() {

    local name=${1}
    local agent_iso=${2}
    local iscsi_disk=${3}

    # create disks
    sudo qemu-img create  -f raw ${iscsi_disk} 100G

    # Create iqn
    sudo targetcli backstores/fileio create name=$name size=100G file_or_dev=${iscsi_disk}

    # Create initiator
    sudo targetcli /iscsi create iqn.2023-01.com.example:$name

    # Create a lun
    sudo targetcli /iscsi/iqn.2023-01.com.example:$name/tpg1/luns create /backstores/fileio/$name

    # Allow access to initiator
    sudo targetcli /iscsi/iqn.2023-01.com.example:$name/tpg1/acls create iqn.2023-01.com.example:initiator01

    # Override iscsi timeout value. Not setting this can result in the error:
    #   Unable to recover from DataOut timeout while in ERL=0, closing iSCSI connection
    sudo targetcli /iscsi/iqn.2023-01.com.example:$name/tpg1/acls/iqn.2023-01.com.example:initiator01 set attribute dataout_timeout=60
    sudo targetcli /iscsi/iqn.2023-01.com.example:$name/tpg1/acls/iqn.2023-01.com.example:initiator01 set attribute dataout_timeout_retries=10

    # Save configuration.
    sudo targetcli / saveconfig

    # Copy the ISO to disk
    sudo dd conv=notrunc if=${agent_iso} of=${iscsi_disk} status=progress
}

function agent_create_iscsi_pxe_file() {

    local name=${1}
    local boot_dir=${2}

cat > "${boot_dir}/agent.x86_64-iscsi.ipxe" << EOF
#!ipxe
set initiator-iqn iqn.2023-01.com.example:initiator01
sanboot --keep iscsi:192.168.145.1::::iqn.2023-01.com.example:${name}
EOF
}
