#!/usr/bin/env bash
set -xe

source common.sh
source ocp_install_env.sh

# This script will create some libvirt VMs do act as "dummy baremetal"
# then configure python-virtualbmc to control them - these can later
# be deployed via the install process similar to how we test TripleO
# Note we copy the playbook so the roles/modules from tripleo-quickstart
# are found without a special ansible.cfg
export ANSIBLE_LIBRARY=./library

ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e "non_root_user=$USER" \
    -e "working_dir=$WORKING_DIR" \
    -e "roles_path=$PWD/roles" \
    -e @tripleo-quickstart-config/metalkube-nodes.yml \
    -e "local_working_dir=$HOME/.quickstart" \
    -e "virthost=$HOSTNAME" \
    -e "platform=$NODES_PLATFORM" \
    -e "baremetal_interface=$INT_IF" \
    -e "provisioning_interface=$PRO_IF" \
    -e @config/environments/dev_privileged_libvirt.yml \
    -i tripleo-quickstart-config/metalkube-inventory.ini \
    -b -vvv tripleo-quickstart-config/metalkube-setup-playbook.yml

# Allow local non-root-user access to libvirt
sudo usermod -a -G "libvirt" $USER

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

# Allow ipmi to the virtual bmc processes that we just started
if ! sudo iptables -C INPUT -i baremetal -p udp -m udp --dport 6230:6235 -j ACCEPT 2>/dev/null ; then
    sudo iptables -I INPUT -i baremetal -p udp -m udp --dport 6230:6235 -j ACCEPT
fi

#Allow access to dualboot.ipxe
if ! sudo iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null ; then
    sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
fi

#Allow access to tftp server for pxeboot
if ! sudo iptables -C INPUT -p udp --dport 69 -j ACCEPT 2>/dev/null ; then
    sudo iptables -I INPUT -p udp --dport 69 -j ACCEPT
fi

# Need to route traffic from the provisioning host.
if [ "$EXT_IF" ]; then
  sudo iptables -t nat -A POSTROUTING --out-interface $EXT_IF -j MASQUERADE
  sudo iptables -A FORWARD --in-interface baremetal -j ACCEPT
fi

# Add access to backend Facet server from remote locations
if ! sudo iptables -C INPUT -p tcp --dport 8080 -j ACCEPT 2>/dev/null ; then
  sudo iptables -I INPUT -p tcp --dport 8080 -j ACCEPT
fi

# Add access to Yarn development server from remote locations
if ! sudo iptables -C INPUT -p tcp --dport 3000 -j ACCEPT 2>/dev/null ; then
  sudo iptables -I INPUT -p tcp --dport 3000 -j ACCEPT
fi

# Need to pass the provision interface for bare metal
if [ "$PRO_IF" ]; then
    echo -e "DEVICE=$PRO_IF\nTYPE=Ethernet\nONBOOT=yes\nNM_CONTROLLED=no\nBOOTPROTO=none\nBRIDGE=provisioning" | sudo dd of=/etc/sysconfig/network-scripts/ifcfg-$PRO_IF
fi

# Internal interface
if [ "$INT_IF" ]; then
    echo -e "DEVICE=baremetal\nTYPE=Bridge\nHWADDR=$MAC\nONBOOT=yes\nNM_CONTROLLED=no\nBOOTPROTO=dhcp" | sudo dd of=/etc/sysconfig/network-scripts/ifcfg-baremetal
    sudo cp /etc/sysconfig/network-scripts/ifcfg-$INT_IF /etc/sysconfig/network-scripts/ifcfg-$INT_IF.orig
    echo -e "DEVICE=$INT_IF\nTYPE=Ethernet\nONBOOT=yes\nNM_CONTROLLED=no\nBOOTPROTO=none\nBRIDGE=baremetal" | sudo dd of=/etc/sysconfig/network-scripts/ifcfg-$INT_IF
    sudo systemctl restart network
fi

# Switch NetworkManager to internal DNS
if [ "$NODES_PLATFORM" == 'libvirt' ]; then
  sudo mkdir -p /etc/NetworkManager/conf.d/
  sudo crudini --set /etc/NetworkManager/conf.d/dnsmasq.conf main dns dnsmasq
  if [ "$ADDN_DNS" ] ; then
    echo "server=$ADDN_DNS" | sudo tee /etc/NetworkManager/dnsmasq.d/upstream.conf
  fi
  if systemctl is-active --quiet NetworkManager; then
    sudo systemctl reload NetworkManager
  else
    sudo systemctl restart NetworkManager
  fi
fi
