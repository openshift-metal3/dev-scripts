#!/usr/bin/env bash
set -xe

source common.sh

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
    -e @config/environments/dev_privileged_libvirt.yml \
    -i tripleo-quickstart-config/metalkube-inventory.ini \
    -b -vvv tripleo-quickstart-config/metalkube-setup-playbook.yml \
    | tee "ansible-$(date -u +%Y%m%d%H%M).log"

# Allow local non-root-user access to libvirt ref
# https://github.com/openshift/installer/blob/master/docs/dev/libvirt-howto.md#make-sure-you-have-permissions-for-qemusystem
if sudo test ! -f /etc/polkit-1/rules.d/80-libvirt.rules ; then
  cat <<EOF | sudo dd of=/etc/polkit-1/rules.d/80-libvirt.rules
polkit.addRule(function(action, subject) {
  if (action.id == "org.libvirt.unix.manage" && subject.local && subject.active && subject.isInGroup("wheel")) {
      return polkit.Result.YES;
  }
});
EOF
fi

# Allow ipmi to the virtual bmc processes that we just started
sudo iptables -I INPUT -i virbr0 -p udp -m udp --dport 6230:6235 -j ACCEPT

# Need to route traffic from the provisioning host.
if [ "$EXT_IF" ]; then
  sudo iptables -t nat -A POSTROUTING --out-interface $EXT_IF -j MASQUERADE
  sudo iptables -A FORWARD --in-interface virbr0 -j ACCEPT
fi

# Need to pass the provision interface for bare metal
if [ "$PRO_IF" ]; then
  sudo ip link set "$PRO_IF" master brovc
fi

# Internal interface
if [ "$INT_IF" ]; then
  sudo ip link set "$INT_IF" master virbr0
fi

# Switch NetworkManager to internal DNS
sudo mkdir -p /etc/NetworkManager/conf.d/
sudo crudini --set /etc/NetworkManager/conf.d/dnsmasq.conf main dns dnsmasq
if [ "$ADDN_DNS" ] ; then
  echo "server=$ADDN_DNS" | tee /etc/NetworkManager/dnsmasq.d/upstream.conf
fi
if systemctl is-active --quiet NetworkManager; then
  sudo systemctl reload NetworkManager
else
  sudo systemctl restart NetworkManager
fi
