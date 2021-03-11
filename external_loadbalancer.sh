#!/bin/bash

set -ex -o pipefail

source common.sh
source network.sh
source utils.sh


sudo firewall-cmd --zone=libvirt --add-port=6443/tcp
sudo firewall-cmd --zone=libvirt --add-port=8080/tcp

haproxy_config="${WORKING_DIR}/haproxy.cfg"
echo $haproxy_config


if [ "$IP_STACK" = "v6" ]
then
     master0=$(nth_ip $EXTERNAL_SUBNET_V6 20)
     master1=$(nth_ip $EXTERNAL_SUBNET_V6 21)
     master2=$(nth_ip $EXTERNAL_SUBNET_V6 22)
     worker0=$(nth_ip $EXTERNAL_SUBNET_V6 23)
     worker1=$(nth_ip $EXTERNAL_SUBNET_V6 24)
else

     master0=$(nth_ip $EXTERNAL_SUBNET_V4 20)
     master1=$(nth_ip $EXTERNAL_SUBNET_V4 21)
     master2=$(nth_ip $EXTERNAL_SUBNET_V4 22)
     worker0=$(nth_ip $EXTERNAL_SUBNET_V4 23)
     worker1=$(nth_ip $EXTERNAL_SUBNET_V4 24)
fi

cat << EOF > "$haproxy_config"
defaults
    mode                    tcp
    log                     global
    timeout connect         10s
    timeout client          1m
    timeout server          1m
frontend main
    bind :::6443 v4v6
    default_backend api
frontend ingress
    bind :::8080  v4v6
    default_backend ingress
backend api
    option  httpchk GET /readyz HTTP/1.0
    option  log-health-checks
    balance roundrobin
    server master-0 ${master0}:6443 check check-ssl inter 1s fall 2 rise 3 verify none
    server master-1 ${master1}:6443 check check-ssl inter 1s fall 2 rise 3 verify none
    server master-2 ${master2}:6443 check check-ssl inter 1s fall 2 rise 3 verify none
backend ingress
    option  httpchk GET /healthz/ready  HTTP/1.0
    option  log-health-checks
    balance roundrobin
    server master-0 ${master0}:80 check check-ssl port 1936 inter 1s fall 2 rise 3 verify none
    server master-1 ${master1}:80 check check-ssl port 1936 inter 1s fall 2 rise 3 verify none
    server master-2 ${master2}:80 check check-ssl port 1936 inter 1s fall 2 rise 3 verify none
    server w-0 ${worker0}:80 check check-ssl port 1936 inter 1s fall 2 rise 3 verify none
    server w-1 ${worker1}:80 check check-ssl port 1936 inter 1s fall 2 rise 3 verify none
EOF

sudo podman run -d  --net host -v "${WORKING_DIR}":/etc/haproxy/:z --entrypoint bash --name extlb quay.io/openshift/origin-haproxy-router  -c 'haproxy -f /etc/haproxy/haproxy.cfg'

sleep 5

if [ "$(curl  --fail  https://$(wrap_if_ipv6 ${PROVISIONING_HOST_EXTERNAL_IP}):6443/version --insecure)" ]; then
    echo " API is available through LB"
else
    echo " Can't access API through  LB"
fi


if [ "$(curl  --fail  --header "Host: console-openshift-console.apps.ostest.test.metalkube.org" http://$(wrap_if_ipv6 ${PROVISIONING_HOST_EXTERNAL_IP}):8080  -I -L --insecure)" ]; then
    echo " Ingress is available through LB"
else
    echo " Can't access Ingress through LB"
fi
