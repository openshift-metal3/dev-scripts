#!/usr/bin/env bash
set -xe

source logging.sh
source common.sh
source utils.sh
source ocp_install_env.sh

# Generate user ssh key
if [ ! -f $HOME/.ssh/id_rsa.pub ]; then
    ssh-keygen -f ~/.ssh/id_rsa -P ""
fi

# root needs a private key to talk to libvirt
# See vm-setup/roles/virtbmc/tasks/configure-vbmc.yml
# in https://github.com/metal3-io/metal3-dev-env.git
# FIXME(shardy) this should be in the ansible role ...
if sudo [ ! -f /root/.ssh/id_rsa_virt_power ]; then
  sudo ssh-keygen -f /root/.ssh/id_rsa_virt_power -P ""
  sudo cat /root/.ssh/id_rsa_virt_power.pub | sudo tee -a /root/.ssh/authorized_keys
fi

# This script will create some libvirt VMs do act as "dummy baremetal"
# then configure python-virtualbmc to control them - these can later
# be deployed via the install process similar to how we test TripleO
# Note we copy the playbook so the roles/modules from tripleo-quickstart
# are found without a special ansible.cfg
# FIXME(shardy) output an error message temporarily since we've broken an interface
export VM_NODES_FILE=${VM_NODES_FILE:-}
if [ ! -z "${VM_NODES_FILE}" ]; then
  echo "VM_NODES_FILE is no longer supported"
  echo "Please use NUM_MASTERS, NUM_WORKERS and VM_EXTRADISKS variables instead"
  exit 1
fi

if [[ "${IP_STACK}" == "v6" ]]; then
  # TODO - move this to metal3-dev-env.
  # This is to address the following error:
  #   "msg": "internal error: Check the host setup: enabling IPv6 forwarding with RA routes without accept_ra set to 2 is likely to cause routes loss. Interfaces to look at: eno2"
  # This comes from libvirt when trying to create the ostestbm network.
  for n in /proc/sys/net/ipv6/conf/* ; do
    if [ -f $n/accept_ra ]; then
      sudo sysctl -w net.ipv6.conf.$(basename $n).accept_ra=2
    fi
  done
fi

ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e @vm_setup_vars.yml \
    -e "cluster_name=${CLUSTER_NAME}" \
    -e "provisioning_network_name=${PROVISIONING_NETWORK_NAME}" \
    -e "baremetal_network_name=${BAREMETAL_NETWORK_NAME}" \
    -e "working_dir=$WORKING_DIR" \
    -e "num_masters=$NUM_MASTERS" \
    -e "num_workers=$NUM_WORKERS" \
    -e "extradisks=$VM_EXTRADISKS" \
    -e "libvirt_firmware=uefi" \
    -e "virthost=$HOSTNAME" \
    -e "vm_platform=$NODES_PLATFORM" \
    -e "manage_baremetal=$MANAGE_BR_BRIDGE" \
    -e "provisioning_url_host=$PROVISIONING_URL_HOST" \
    -e "nodes_file=$NODES_FILE" \
    -e "virtualbmc_base_port=$VBMC_BASE_PORT" \
    -e "master_hostname_format=$MASTER_HOSTNAME_FORMAT" \
    -e "worker_hostname_format=$WORKER_HOSTNAME_FORMAT" \
    -i ${VM_SETUP_PATH}/inventory.ini \
    -b -vvv ${VM_SETUP_PATH}/setup-playbook.yml

# Allow local non-root-user access to libvirt
# Restart libvirtd service to get the new group membership loaded
if ! id $USER | grep -q libvirt; then
  sudo usermod -a -G "libvirt" $USER
  sudo systemctl restart libvirtd
fi

# As per https://github.com/openshift/installer/blob/master/docs/dev/libvirt-howto.md#configure-default-libvirt-storage-pool
# Usually virt-manager/virt-install creates this: https://www.redhat.com/archives/libvir-list/2008-August/msg00179.html
if ! virsh pool-uuid default > /dev/null 2>&1 ; then
    virsh pool-define /dev/stdin <<EOF
<pool type='dir'>
  <name>default</name>
  <target>
    <path>/var/lib/libvirt/images</path>
  </target>
</pool>
EOF
    virsh pool-start default
    virsh pool-autostart default
fi

if [ "${RHEL8}" = "True" ] || [ "${CENTOS8}" = "True" ] ; then
    ZONE="\nZONE=libvirt"

    sudo systemctl enable --now firewalld
fi

if [ "$MANAGE_PRO_BRIDGE" == "y" ]; then
    # Adding an IP address in the libvirt definition for this network results in
    # dnsmasq being run, we don't want that as we have our own dnsmasq, so set
    # the IP address here
    if [ ! -e /etc/sysconfig/network-scripts/ifcfg-${PROVISIONING_NETWORK_NAME} ] ; then
        if [[ "$(ipversion $PROVISIONING_HOST_IP)" == "6" ]]; then
            echo -e "DEVICE=${PROVISIONING_NETWORK_NAME}\nTYPE=Bridge\nONBOOT=yes\nNM_CONTROLLED=no\nIPV6_AUTOCONF=no\nIPV6INIT=yes\nIPV6ADDR=${PROVISIONING_HOST_IP}/64${ZONE}" | sudo dd of=/etc/sysconfig/network-scripts/ifcfg-${PROVISIONING_NETWORK_NAME}
        else
            echo -e "DEVICE=${PROVISIONING_NETWORK_NAME}\nTYPE=Bridge\nONBOOT=yes\nNM_CONTROLLED=no\nBOOTPROTO=static\nIPADDR=$PROVISIONING_HOST_IP\nNETMASK=$PROVISIONING_NETMASK${ZONE}" | sudo dd of=/etc/sysconfig/network-scripts/ifcfg-${PROVISIONING_NETWORK_NAME}
       fi
    fi
    sudo ifdown ${PROVISIONING_NETWORK_NAME} || true
    sudo ifup ${PROVISIONING_NETWORK_NAME}

    # Need to pass the provision interface for bare metal
    if [ "$PRO_IF" ]; then
        echo -e "DEVICE=$PRO_IF\nTYPE=Ethernet\nONBOOT=yes\nNM_CONTROLLED=no\nBRIDGE=${PROVISIONING_NETWORK_NAME}" | sudo dd of=/etc/sysconfig/network-scripts/ifcfg-$PRO_IF
        sudo ifdown $PRO_IF || true
        sudo ifup $PRO_IF
        # Need to ifup the provisioning bridge again because ifdown $PRO_IF
        # will bring down the bridge as well.
        sudo ifup ${PROVISIONING_NETWORK_NAME}
    fi
fi

if [ "$MANAGE_INT_BRIDGE" == "y" ]; then
    # Create the baremetal bridge
    if [ ! -e /etc/sysconfig/network-scripts/ifcfg-${BAREMETAL_NETWORK_NAME} ] ; then
        echo -e "DEVICE=${BAREMETAL_NETWORK_NAME}\nTYPE=Bridge\nONBOOT=yes\nNM_CONTROLLED=no${ZONE}" | sudo dd of=/etc/sysconfig/network-scripts/ifcfg-${BAREMETAL_NETWORK_NAME}
    fi
    sudo ifdown ${BAREMETAL_NETWORK_NAME} || true
    sudo ifup ${BAREMETAL_NETWORK_NAME}

    # Add the internal interface to it if requests, this may also be the interface providing
    # external access so we need to make sure we maintain dhcp config if its available
    if [ "$INT_IF" ]; then
        echo -e "DEVICE=$INT_IF\nTYPE=Ethernet\nONBOOT=yes\nNM_CONTROLLED=no\nBRIDGE=${BAREMETAL_NETWORK_NAME}" | sudo dd of=/etc/sysconfig/network-scripts/ifcfg-$INT_IF
        if [[ -n "${EXTERNAL_SUBNET_V6}" ]]; then
             grep -q BOOTPROTO /etc/sysconfig/network-scripts/ifcfg-${BAREMETAL_NETWORK_NAME} || (echo -e "BOOTPROTO=none\nIPV6INIT=yes\nIPV6_AUTOCONF=yes\nDHCPV6C=yes\nDHCPV6C_OPTIONS='-D LL'\n" | sudo tee -a /etc/sysconfig/network-scripts/ifcfg-${BAREMETAL_NETWORK_NAME})
        else
           if sudo nmap --script broadcast-dhcp-discover -e $INT_IF | grep "IP Offered" ; then
               grep -q BOOTPROTO /etc/sysconfig/network-scripts/ifcfg-${BAREMETAL_NETWORK_NAME} || (echo -e "\nBOOTPROTO=dhcp\n" | sudo tee -a /etc/sysconfig/network-scripts/ifcfg-${BAREMETAL_NETWORK_NAME})
           fi
       fi
        sudo systemctl restart network
    fi
fi

# If there were modifications to the /etc/sysconfig/network-scripts/ifcfg-*
# files, it is required to enable the network service
if [ "$MANAGE_INT_BRIDGE" == "y" ] || [ "$MANAGE_PRO_BRIDGE" == "y" ]; then
  sudo systemctl enable network
fi

# restart the libvirt network so it applies an ip to the bridge
if [ "$MANAGE_BR_BRIDGE" == "y" ] ; then
    sudo virsh net-destroy ${BAREMETAL_NETWORK_NAME}
    sudo virsh net-start ${BAREMETAL_NETWORK_NAME}
    if [ "$INT_IF" ]; then #Need to bring UP the NIC after destroying the libvirt network
        sudo ifup $INT_IF
    fi
fi

IPTABLES=iptables
if [[ "$(ipversion $PROVISIONING_HOST_IP)" == "6" ]]; then
    IPTABLES=ip6tables
fi

ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e "{use_firewalld: $USE_FIREWALLD}" \
    -e "provisioning_interface=$PROVISIONING_NETWORK_NAME" \
    -e "baremetal_interface=$BAREMETAL_NETWORK_NAME" \
    -e "{provisioning_host_ports: [80, ${LOCAL_REGISTRY_PORT}, 8000]}" \
    -e "vbmc_port_range=$VBMC_BASE_PORT:$VBMC_MAX_PORT" \
    -i ${VM_SETUP_PATH}/inventory.ini \
    -b -vvv ${VM_SETUP_PATH}/firewall.yml

# FIXME(stbenjam): ansbile firewalld module doesn't seem to be doing the right thing
if [ "$USE_FIREWALLD" == "True" ]; then
  sudo firewall-cmd --zone=libvirt --change-interface=provisioning
  sudo firewall-cmd --zone=libvirt --change-interface=baremetal
fi

# Need to route traffic from the provisioning host.
if [ "$EXT_IF" ]; then
  sudo $IPTABLES -t nat -A POSTROUTING --out-interface $EXT_IF -j MASQUERADE
  sudo $IPTABLES -A FORWARD --in-interface ${BAREMETAL_NETWORK_NAME} -j ACCEPT
fi

# Switch NetworkManager to internal DNS
if [ "$MANAGE_BR_BRIDGE" == "y" ] ||  [ "$NODES_PLATFORM" = "assisted" ]; then
  sudo mkdir -p /etc/NetworkManager/conf.d/
  ansible localhost -b -m ini_file -a "path=/etc/NetworkManager/conf.d/dnsmasq.conf section=main option=dns value=dnsmasq"
  if [ "$ADDN_DNS" ] ; then
    echo "server=$ADDN_DNS" | sudo tee /etc/NetworkManager/dnsmasq.d/upstream.conf
  fi
  if systemctl is-active --quiet NetworkManager; then
    sudo systemctl reload NetworkManager
  else
    sudo systemctl restart NetworkManager
  fi
fi

# Add a /etc/hosts entry for $LOCAL_REGISTRY_DNS_NAME
sudo sed -i "/${LOCAL_REGISTRY_DNS_NAME}/d" /etc/hosts
echo "${PROVISIONING_HOST_EXTERNAL_IP} ${LOCAL_REGISTRY_DNS_NAME}" | sudo tee -a /etc/hosts

# Remove any previous file, or podman login panics when reading the
# blank authfile with a "assignment to entry in nil map" error
rm -f ${REGISTRY_CREDS}
if [[ ! -z "${MIRROR_IMAGES}" || $(env | grep "_LOCAL_IMAGE=") ]]; then
    # create authfile for local registry
    sudo podman login --authfile ${REGISTRY_CREDS} \
        -u ${REGISTRY_USER} -p ${REGISTRY_PASS} \
        ${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}
else
    # Create a blank authfile in order to have something valid when we read it in 04_setup_ironic.sh
    echo '{}' | sudo dd of=${REGISTRY_CREDS}
fi

# metal3-dev-env contains a script to run the openstack client in a
# container, place a link to it in $PATH if we don't already have the
# openstack command installed
OPENSTACKCLIENT_PATH="${OPENSTACKCLIENT_PATH:-/usr/local/bin/openstack}"
if ! command -v openstack | grep -v "${OPENSTACKCLIENT_PATH}"; then
	  sudo ln -sf "${METAL3_DEV_ENV_PATH}/openstackclient.sh" "${OPENSTACKCLIENT_PATH}"
fi
