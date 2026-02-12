#!/usr/bin/env bash
set -euxo pipefail

source logging.sh
source common.sh
source network.sh
source utils.sh
source validation.sh
source oc_mirror.sh

early_deploy_validation

#
# Manage libvirtd services based on OS
# Get a dedicated method, making it easier to duplicate
# or move in order to expose it to some other parts if needed.
# This is the same method as defined in metal3-dev-env via that
# commit:
# https://github.com/metal3-io/metal3-dev-env/pull/1313/commits/a6a79685986f9d7cb18c4eb680ee4d2a759e99dc
#
manage_libvirtd() {
  case ${DISTRO} in
      centos9|rhel9|almalinux9|rocky9)
          for i in qemu interface network nodedev nwfilter secret storage proxy; do
              sudo systemctl enable --now virt${i}d.socket
              sudo systemctl enable --now virt${i}d-ro.socket
              sudo systemctl enable --now virt${i}d-admin.socket
          done
          ;;
      *)
          sudo systemctl restart libvirtd.service
        ;;
esac
}

# Generate user ssh key
if [ ! -f $HOME/.ssh/id_rsa.pub ]; then
    ssh-keygen -f ~/.ssh/id_rsa -t rsa -P ""
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

# If deploying to a real baremetal environment, we need to make
# sure all nodes are powered down
if [[ "${NODES_PLATFORM}" == "baremetal" ]] && [ -n "$NODES_FILE" ] ; then
    set +x
    cat $NODES_FILE | jq -r '.nodes[].driver_info | ( .address + " " + .username + " " + .password ) ' |
    while read ADDRESS USER PASSWORD ; do
        if [[ $ADDRESS =~ ^ipmi://([^:]*)(:([0-9]+))?$ ]] ; then
            IPMIIP=${BASH_REMATCH[1]}
            IPMIPORT=${BASH_REMATCH[3]:-623}
            ipmitool -I lanplus -H $IPMIIP -p $IPMIPORT -U $USER -P $PASSWORD power off || echo "WARNING($?): Failed power down of $ADDRESS"
        elif [[ $ADDRESS =~ ^(redfish.*://)(.*)$ ]] ; then
            SCHEME="https://"
            SYSTEM="${BASH_REMATCH[2]}"
            if [[ ${BASH_REMATCH[1]} =~ http: ]] ; then
                SCHEME="http://"
            fi
            SYSTEMURL="${SCHEME}${SYSTEM}"
            curl -u $USER:$PASSWORD -k -H 'Content-Type: application/json' $SYSTEMURL/Actions/ComputerSystem.Reset -d '{"ResetType": "ForceOff"}' || echo "WARNING($?): Failed power down of $ADDRESS"
        else
            # TODO: Add support for other protocols
            echo "WARNING: Skipping power down of $ADDRESS"
        fi
    done
    set -x
fi

# TODO - move this to metal3-dev-env.
# This is to address the following error:
#   "msg": "internal error: Check the host setup: enabling IPv6 forwarding with RA routes without accept_ra set to 2 is likely to cause routes loss. Interfaces to look at: eno2"
# This comes from libvirt when trying to create the ostestbm network.
for n in /proc/sys/net/ipv6/conf/* ; do
  if [ -f $n/accept_ra ]; then
    sudo sysctl -w net/ipv6/conf/$(basename $n)/accept_ra=2
  fi
done

export ANSIBLE_FORCE_COLOR=true

if use_registry ""; then
    setup_local_registry
fi

# Configure a local proxy to be used for the installation
if [[ ! -z "${INSTALLER_PROXY}" ]]; then
  generate_proxy_conf > ${WORKING_DIR}/squid.conf

  sudo podman run -d --rm \
    --net host \
    --volume ${WORKING_DIR}/squid.conf:/etc/squid/squid.conf \
    --name ds-squid \
    --dns 127.0.0.1 \
    --add-host=virthost.ostest.test.metalkube.org:$PROVISIONING_HOST_EXTERNAL_IP \
    quay.io/sameersbn/squid:latest
fi

sudo systemctl enable --now firewalld

# Configure an NTP server for use by the cluster, this is especially
# important on IPv6 where the cluster doesn't have outbound internet
# access.
configure_chronyd

export VNC_CONSOLE=true
if [[ $(uname -m) == "aarch64" ]]; then
  VNC_CONSOLE=false
  echo "libvirt_cdrombus: scsi" >> vm_setup_vars.yml
fi

ansible-playbook \
    -e @vm_setup_vars.yml \
    -e "ironic_prefix=${CLUSTER_NAME}_" \
    -e "cluster_name=${CLUSTER_NAME}" \
    -e "provisioning_network_name=${PROVISIONING_NETWORK_NAME}" \
    -e "baremetal_network_name=${BAREMETAL_NETWORK_NAME}" \
    -e "working_dir=$WORKING_DIR" \
    -e "num_masters=$NUM_MASTERS" \
    -e "num_workers=$NUM_WORKERS" \
    -e "num_extraworkers=$NUM_EXTRA_WORKERS" \
    -e "libvirt_firmware=$LIBVIRT_FIRMWARE" \
    -e "virthost=$HOSTNAME" \
    -e "vm_platform=$NODES_PLATFORM" \
    -e "sushy_ignore_boot_device=$REDFISH_EMULATOR_IGNORE_BOOT_DEVICE" \
    -e "manage_baremetal=$MANAGE_BR_BRIDGE" \
    -e "provisioning_url_host=${PROVISIONING_URL_HOST:-}" \
    -e "nodes_file=$NODES_FILE" \
    -e "virtualbmc_base_port=$VBMC_BASE_PORT" \
    -e "master_hostname_format=$MASTER_HOSTNAME_FORMAT" \
    -e "worker_hostname_format=$WORKER_HOSTNAME_FORMAT" \
    -e "libvirt_arch=$(uname -m)" \
    -e "enable_vnc_console=$VNC_CONSOLE" \
    -i ${VM_SETUP_PATH}/inventory.ini \
    -b -vvv ${VM_SETUP_PATH}/setup-playbook.yml

# NOTE(elfosardo): /usr/share/OVMF/OVMF_CODE.fd does not exist in the ovmf
# package anymore, so we need to create a link to that until metal3-dev-env
# fixes that, probably when switching to UEFI by default
if ! [[ -f /usr/share/OVMF/OVMF_CODE.fd || -L /usr/share/OVMF/OVMF_CODE.fd ]]; then
  sudo ln -s /usr/share/edk2/ovmf/OVMF_CODE.fd /usr/share/OVMF/
fi

if [ ${NUM_EXTRA_WORKERS} -ne 0 ]; then
  ORIG_NODES_FILE="${NODES_FILE}.orig"
  cp -f ${NODES_FILE} ${ORIG_NODES_FILE}
  sudo chown -R $USER:$GROUP ${NODES_FILE}
  jq "{nodes: .nodes[:$((NUM_MASTERS + NUM_ARBITERS + NUM_WORKERS))]}" ${ORIG_NODES_FILE} | tee ${NODES_FILE}
  jq "{nodes: .nodes[-${NUM_EXTRA_WORKERS}:]}" ${ORIG_NODES_FILE} | tee ${EXTRA_NODES_FILE}
fi

ZONE="\nZONE=libvirt"

# Allow local non-root-user access to libvirt
if ! id $USER | grep -q libvirt; then
  sudo usermod -a -G "libvirt" $USER
fi

# This method, defined in common.sh, will either ensure sockets are up'n'running
# for CS9 and RHEL9, or restart the libvirtd.service for other DISTRO
manage_libvirtd

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

# shellcheck disable=SC1091
source /etc/os-release

if [ "$MANAGE_PRO_BRIDGE" == "y" ]; then
    # Adding an IP address in the libvirt definition for this network results in
    # dnsmasq being run, we don't want that as we have our own dnsmasq, so set
    # the IP address here
    if [ ! -e /etc/NetworkManager/system-connections/${PROVISIONING_NETWORK_NAME}.nmconnection ]; then
        if [ "$(ipversion $PROVISIONING_HOST_IP)" == "6" ]; then
            sudo tee -a /etc/NetworkManager/system-connections/${PROVISIONING_NETWORK_NAME}.nmconnection <<EOF
[connection]
id=${PROVISIONING_NETWORK_NAME}
type=bridge
interface-name=${PROVISIONING_NETWORK_NAME}
[bridge]
stp=false
[ipv4]
method=disabled
[ipv6]
addr-gen-mode=eui64
address1=${PROVISIONING_HOST_IP}/64
method=manual
EOF
        else
            sudo tee -a /etc/NetworkManager/system-connections/${PROVISIONING_NETWORK_NAME}.nmconnection <<EOF
[connection]
id=${PROVISIONING_NETWORK_NAME}
type=bridge
interface-name=${PROVISIONING_NETWORK_NAME}
[bridge]
stp=false
[ipv4]
address1=${PROVISIONING_HOST_IP}/$PROVISIONING_NETMASK
method=manual
[ipv6]
addr-gen-mode=eui64
method=disabled
EOF
        fi
        sudo chmod 600 /etc/NetworkManager/system-connections/${PROVISIONING_NETWORK_NAME}.nmconnection
        sudo nmcli con load /etc/NetworkManager/system-connections/${PROVISIONING_NETWORK_NAME}.nmconnection
    fi
    sudo nmcli con up ${PROVISIONING_NETWORK_NAME}

    # Need to pass the provision interface for bare metal
    if [ "$PRO_IF" ]; then
        sudo tee -a /etc/NetworkManager/system-connections/${PRO_IF}.nmconnection <<EOF
[connection]
id=${PRO_IF}
type=ethernet
interface-name=${PRO_IF}
master=${PROVISIONING_NETWORK_NAME}
slave-type=bridge
EOF
        sudo chmod 600 /etc/NetworkManager/system-connections/${PRO_IF}.nmconnection
        sudo nmcli con load /etc/NetworkManager/system-connections/${PRO_IF}.nmconnection
        sudo nmcli con up ${PRO_IF}
    fi
fi

if [ "$MANAGE_INT_BRIDGE" == "y" ]; then
    # Create the baremetal bridge
    sudo tee /etc/NetworkManager/system-connections/${BAREMETAL_NETWORK_NAME}.nmconnection <<EOF
[connection]
id=${BAREMETAL_NETWORK_NAME}
type=bridge
interface-name=${BAREMETAL_NETWORK_NAME}
autoconnect=true
[bridge]
stp=false
[ipv6]
addr-gen-mode=stable-privacy
method=ignore
EOF
    sudo chmod 600 /etc/NetworkManager/system-connections/${BAREMETAL_NETWORK_NAME}.nmconnection
    sudo nmcli con load /etc/NetworkManager/system-connections/${BAREMETAL_NETWORK_NAME}.nmconnection
    sudo nmcli con up ${BAREMETAL_NETWORK_NAME}
fi

    # Add the internal interface to it if requests, this may also be the interface providing
    # external access so we need to make sure we maintain dhcp config if its available
    if [ "$INT_IF" ]; then
        sudo tee /etc/NetworkManager/system-connections/${INT_IF}.nmconnection <<EOF
[connection]
id=${INT_IF}
type=ethernet
interface-name=${INT_IF}
master=${BAREMETAL_NETWORK_NAME}
slave-type=bridge
EOF
        sudo chmod 600 /etc/NetworkManager/system-connections/${INT_IF}.nmconnection
        sudo nmcli con load /etc/NetworkManager/system-connections/${INT_IF}.nmconnection

        if [[ -n "${EXTERNAL_SUBNET_V6}" ]]; then
            sudo nmcli con mod ${BAREMETAL_NETWORK_NAME} ipv6.addr-gen-mode eui64
            sudo nmcli con mod ${BAREMETAL_NETWORK_NAME} ipv6.method ignore
        else
            if sudo nmap --script broadcast-dhcp-discover -e $INT_IF | grep "IP Offered" ; then
                if [ "$(ipversion $PROVISIONING_HOST_IP)" == "6" ]; then
                    sudo nmcli con mod ${BAREMETAL_NETWORK_NAME} ipv6.method auto
                else
                    sudo nmcli con mod ${BAREMETAL_NETWORK_NAME} ipv4.method auto
            fi
      fi
      sudo nmcli con up ${INT_IF}
    fi
fi

# If there were modifications to the network configuration
# files, it is required to enable the network service
if [ "$MANAGE_INT_BRIDGE" == "y" ] || [ "$MANAGE_PRO_BRIDGE" == "y" ]; then
  sudo systemctl enable NetworkManager
fi

# restart the libvirt network so it applies an ip to the bridge
if [ "$MANAGE_BR_BRIDGE" == "y" ] ; then
    sudo virsh net-destroy ${BAREMETAL_NETWORK_NAME}
    # have some delay between disabling the network on libvirt
    # and deleting it from NM to avoid race conditions
    sleep 1
    sudo nmcli con del ${BAREMETAL_NETWORK_NAME}
    # have some delay between deleting the network on NM
    # and restarting it from libvirt to avoid race conditions
    sleep 1
    sudo virsh net-start ${BAREMETAL_NETWORK_NAME}
    # Needed in IPv6 on some EL9 hosts for the bootstrap VM to get an IP
    echo 0 | sudo dd of=/proc/sys/net/ipv6/conf/${BAREMETAL_NETWORK_NAME}/addr_gen_mode
    if [ "$INT_IF" ]; then #Need to bring UP the NIC after destroying the libvirt network
        sudo nmcli con up ${INT_IF}
    fi
fi

# IPv6 bridge interfaces will remain in DOWN state with NO-CARRIER unless an interface is added,
# so add a dummy interface to ensure the bridge comes up
if [[ -n "${EXTERNAL_SUBNET_V6}" ]] && [ ! "$INT_IF" ]; then
    sudo ip link add name bm-ipv6-dummy up master ${BAREMETAL_NETWORK_NAME} type dummy || true
fi
if [[ "${PROVISIONING_NETWORK}" =~ : ]] && [ ! "$PRO_IF" ] ; then
    sudo ip link add name pro-ipv6-dummy up master ${PROVISIONING_NETWORK_NAME} type dummy || true
fi

IPTABLES=iptables
if [[ "$(ipversion $PROVISIONING_HOST_IP)" == "6" ]]; then
    IPTABLES=ip6tables
fi

ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e "{use_firewalld: True}" \
    -e "provisioning_interface=$PROVISIONING_NETWORK_NAME" \
    -e "external_interface=$BAREMETAL_NETWORK_NAME" \
    -e "{vm_host_ports: [80, ${LOCAL_REGISTRY_PORT}, 8000, ${INSTALLER_PROXY_PORT}, ${AGENT_BOOT_SERVER_PORT}, 3260]}" \
    -e "vbmc_port_range=$VBMC_BASE_PORT:$VBMC_MAX_PORT" \
    -i ${VM_SETUP_PATH}/inventory.ini \
    -b -vvv ${VM_SETUP_PATH}/firewall.yml

# Need to route traffic from the provisioning host.
if [ "$EXT_IF" ]; then
  sudo $IPTABLES -t nat -A POSTROUTING --out-interface $EXT_IF -j MASQUERADE
  sudo $IPTABLES -A FORWARD --in-interface ${BAREMETAL_NETWORK_NAME} -j ACCEPT
fi

# Switch NetworkManager to internal DNS
if [ "$MANAGE_BR_BRIDGE" == "y" ]; then
  switch_to_internal_dns
fi

# Add a /etc/hosts entry for $LOCAL_REGISTRY_DNS_NAME
sudo sed -i "/${LOCAL_REGISTRY_DNS_NAME}/d" /etc/hosts
echo "${PROVISIONING_HOST_EXTERNAL_IP} ${LOCAL_REGISTRY_DNS_NAME}" | sudo tee -a /etc/hosts

if use_registry "podman"; then
    # Remove any previous file, or podman login panics when reading the
    # blank authfile with a "assignment to entry in nil map" error
    rm -f ${REGISTRY_CREDS}
    # create authfile for local registry
    sudo podman login --authfile ${REGISTRY_CREDS} \
        -u ${REGISTRY_USER} -p ${REGISTRY_PASS} \
        ${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}
elif ! use_registry "quay"; then
    # Create a blank authfile in order to have something valid when we read it in 04_setup_ironic.sh
    echo '{}' | sudo dd of=${REGISTRY_CREDS}
fi
# Since podman 2.2.1 the REGISTRY_CREDS file gets written out as
# o600, where as in previous versions it was 644 - to enable reading
# as $USER elsewhere we chown here, but in future we should probably
# consider moving all podman calls to rootless mode (e.g remove sudo)
sudo chown $USER:$USER ${REGISTRY_CREDS}
ls -l ${REGISTRY_CREDS}

# metal3-dev-env contains a script to run the baremetal ironic client in a
# container, place a link to it if its not installed
IRONICCLIENT_PATH="${IRONICCLIENT_PATH:-/usr/local/bin/baremetal}"
if ! command -v baremetal | grep -v "${IRONICCLIENT_PATH}"; then
    sudo ln -sf "${METAL3_DEV_ENV_PATH}/openstackclient.sh" "${IRONICCLIENT_PATH}"
fi

# Block Multicast with ebtables
if [ "${DISABLE_MULTICAST:-false}" == "true" ]; then
    for dst in 224.0.0.251 224.0.0.18; do
        sudo ebtables -A INPUT --pkttype-type multicast -p ip4 --ip-dst ${dst} -j DROP
        sudo ebtables -A FORWARD --pkttype-type multicast -p ip4 --ip-dst ${dst} -j DROP
        sudo ebtables -A OUTPUT --pkttype-type multicast -p ip4 --ip-dst ${dst} -j DROP
    done

    for dst in ff02::fb ff02::12; do
        sudo ebtables -A INPUT --pkttype-type multicast -p ip6 --ip6-dst ${dst} -j DROP
        sudo ebtables -A FORWARD --pkttype-type multicast -p ip6 --ip6-dst ${dst} -j DROP
        sudo ebtables -A OUTPUT --pkttype-type multicast -p ip6 --ip6-dst ${dst} -j DROP
    done
fi

if [[ ! -z "${BOND_PRIMARY_INTERFACE:-}" ]]; then

    setup_bond master $NUM_MASTERS
    setup_bond worker $NUM_WORKERS
fi

# We should have both virsh networks started by this point.
# Let's do a quick validation here before moving to the next
# stage
sudo virsh net-list | grep ${PROVISIONING_NETWORK_NAME} || sudo virsh net-start ${PROVISIONING_NETWORK_NAME}
sudo virsh net-list | grep ${BAREMETAL_NETWORK_NAME} || sudo virsh net-start ${BAREMETAL_NETWORK_NAME}


# Setup a single nfs export for image registry
if [ "${PERSISTENT_IMAGEREG}" == true ] ; then
    sudo rm -rf /opt/dev-scripts/nfsshare /etc/exports.d/dev-scripts.exports
    sudo mkdir -p /opt/dev-scripts/nfsshare/1
    [ -n "${EXTERNAL_SUBNET_V4:-}" ] && echo "/opt/dev-scripts/nfsshare ${EXTERNAL_SUBNET_V4}(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports.d/dev-scripts.exports
    [ -n "${EXTERNAL_SUBNET_V6:-}" ] && echo "/opt/dev-scripts/nfsshare ${EXTERNAL_SUBNET_V6}(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports.d/dev-scripts.exports
    sudo chown -R nobody:nobody /opt/dev-scripts/nfsshare
    sudo chmod -R 777 /opt/dev-scripts/nfsshare
    sudo firewall-cmd --zone=libvirt  --add-port=2049/tcp
    sudo systemctl start nfs-server
    sudo exportfs -a
fi
