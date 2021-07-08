#!/usr/bin/bash

metallb_dir="$(dirname $(readlink -f $0))"
source ${metallb_dir}/metallb_common.sh

## configure metallb
# create metallb yaml file based on image base/tag
metallb_yaml=$(mktemp --tmpdir "metallb--XXXXXXXXXX")
python << EOF >> ${metallb_yaml}
from jinja2 import Environment, FileSystemLoader
tpl = Environment(loader=FileSystemLoader('${metallb_dir}/', encoding='utf8')).get_template('metallb.yaml.j2')
print("%s"%tpl.render({'metallb_image_base':u'${METALLB_IMAGE_BASE}', 'metallb_image_tag':u'${METALLB_IMAGE_TAG}'}))
EOF

# apply to OCP
oc apply -f ${metallb_dir}/namespace.yaml
oc adm policy add-scc-to-user privileged -n metallb-system -z speaker
oc apply -f ${metallb_yaml}
oc apply -f ${metallb_dir}/config_l2.yaml
oc create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"

sudo ip route add 192.168.10.0/24 dev ${BAREMETAL_NETWORK_NAME}
