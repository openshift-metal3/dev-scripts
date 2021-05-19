#!/usr/bin/bash

export METALLB_REPO=${METALLB_REPO:-https://github.com/metallb/metallb.git}
[[ -d /usr/local/go ]] && export PATH=${PATH}:/usr/local/go/bin

if [ ! -d ./metallb ]; then
	git clone $METALLB_REPO
fi
cd metallb
git checkout dev/support-e2e-non-kind-env

pip3 install --user -r ./dev-env/requirements.txt
inv e2etest --kubeconfig=$(readlink -f ../../ocp/ostest/auth/kubeconfig) \
	--service-pod-port=8080 --system-namespaces="metallb-system" --skip-docker
