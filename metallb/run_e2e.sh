#!/usr/bin/bash

export METALLB_REPO=${METALLB_REPO:-https://github.com/metallb/metallb.git}
[[ -d /usr/local/go ]] && export PATH=${PATH}:/usr/local/go/bin

if [ ! -d ./metallb ]; then
	git clone $METALLB_REPO
fi
cd metallb

# add firewalld rules
sudo firewall-cmd --zone=libvirt --permanent --add-port=179/tcp
sudo firewall-cmd --zone=libvirt --add-port=179/tcp
sudo firewall-cmd --zone=libvirt --permanent --add-port=180/tcp
sudo firewall-cmd --zone=libvirt --add-port=180/tcp

SKIP="none"
if [ "${IP_STACK}" = "v4" ]; then SKIP="${SKIP}\|IPV6"; fi
if [ "${IP_STACK}" = "dual" ]; then SKIP="${SKIP}\|IPV6"; fi
if [ "${IP_STACK}" = "v6" ]; then SKIP="${SKIP}\|IPV4\|BGP"; fi
echo "Skipping ${SKIP}"

pip3 install --user -r ./dev-env/requirements.txt
export PATH=${PATH}:${HOME}/.local/bin
export CONTAINER_RUNTIME=podman
export RUN_FRR_CONTAINER_ON_HOST_NETWORK=true
export PROVISIONING_HOST_EXTERNAL_IPV4=${PROVISIONING_HOST_EXTERNAL_IP}
inv e2etest --kubeconfig=$(readlink -f ../../ocp/ostest/auth/kubeconfig) \
	--service-pod-port=8080 --system-namespaces="metallb-system" --skip-docker \
	--ipv4-service-range=192.168.10.0/24 --ipv6-service-range=fc00:f853:0ccd:e799::/124 \
	--skip=${SKIP}
