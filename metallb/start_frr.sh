#!/usr/bin/bash

metallb_dir="$(dirname $(readlink -f $0))"

source ${metallb_dir}/../common.sh
source ${metallb_dir}/../network.sh

## kill frr container if running
set +e
sudo podman inspect frr 2>/dev/null > /dev/null
if [[ $? -eq 0 ]]; then
	sudo podman kill frr
fi
set -e

## configure frr
# cleanup frr directory
[[ -d ${metallb_dir}/frr ]] &&
	sudo rm -rf ${metallb_dir}/frr

# add firewalld rules
sudo firewall-cmd --zone=libvirt --permanent --add-port=179/tcp
sudo firewall-cmd --zone=libvirt --add-port=179/tcp

# copy frr template
cp -r ${metallb_dir}/frr_template ${metallb_dir}/frr

# get node IP address
# XXX: need to check v4/v6 dual stack case
node_iplist=$(oc get node -o jsonpath='{.items[*].status.addresses[0].address}')
python << EOF >> ${metallb_dir}/frr/bgpd.conf
from jinja2 import Environment, FileSystemLoader
tpl = Environment(loader=FileSystemLoader('${metallb_dir}/frr', encoding='utf8')).get_template('bgpd.conf.j2')
print("%s"%tpl.render({'nodes_ip':u'${node_iplist}'.split(' ')}))
EOF

sudo podman run -d --privileged --network host -it --rm --name frr --volume "${metallb_dir}/frr:/etc/frr" docker.io/frrouting/frr:v7.5.1
