#!/usr/bin/bash

metallb_dir="$(dirname $(readlink -f $0))"
source ${metallb_dir}/metallb_common.sh

# configure metallb through metallb-operator
${metallb_dir}/deploy_operator.sh
oc apply -f ${metallb_dir}/metallb.yaml
oc adm policy add-scc-to-user privileged -n metallb-system -z speaker

sudo ip route add 192.168.10.0/24 dev ${BAREMETAL_NETWORK_NAME}
