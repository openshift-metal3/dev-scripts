#!/usr/bin/bash

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

source $SCRIPTDIR/common.sh
source $SCRIPTDIR/network.sh

cp ${KUBECONFIG} ${HOME}/admin.conf

[[ -d /usr/local/go ]] && export PATH=${PATH}:/usr/local/go/bin

git clone https://github.com/oribon/ovn-kubernetes.git -b ex_gw_e2e_on_host
cd ovn-kubernetes/test

# nc tcp listener port
sudo firewall-cmd --zone=libvirt --permanent --add-port=91/tcp
sudo firewall-cmd --zone=libvirt --add-port=91/tcp
# nc udp listener port
sudo firewall-cmd --zone=libvirt --permanent --add-port=90/udp
sudo firewall-cmd --zone=libvirt --add-port=90/udp
# BFD control packets
sudo firewall-cmd --zone=libvirt --permanent --add-port=3784/udp
sudo firewall-cmd --zone=libvirt --add-port=3784/udp
# BFD echo packets
sudo firewall-cmd --zone=libvirt --permanent --add-port=3785/udp
sudo firewall-cmd --zone=libvirt --add-port=3785/udp
# BFD multihop packets
sudo firewall-cmd --zone=libvirt --permanent --add-port=4784/udp
sudo firewall-cmd --zone=libvirt --add-port=4784/udp

if [ "${IP_STACK}" = "v4" ]; then
	export OVN_TEST_EX_GW_IPV4=${PROVISIONING_HOST_EXTERNAL_IP}
	export OVN_TEST_EX_GW_IPV6=1111:1:1::1
elif [ "${IP_STACK}" = "v6" ]; then
	export OVN_TEST_EX_GW_IPV4=1.1.1.1
	export OVN_TEST_EX_GW_IPV6=${PROVISIONING_HOST_EXTERNAL_IP}
elif [ "${IP_STACK}" = "v4v6" ]; then
	export OVN_TEST_EX_GW_IPV4=${PROVISIONING_HOST_EXTERNAL_IP}
	export OVN_TEST_EX_GW_IPV6=1111:1:1::1
fi

export PATH=${PATH}:${HOME}/.local/bin
export CONTAINER_RUNTIME=podman
export OVN_TEST_EX_GW_NETWORK=host
make control-plane WHAT="e2e non-vxlan external gateway through a gateway pod\|e2e multiple external gateway validation"
