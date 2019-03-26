#!/usr/bin/bash

set -eux
source utils.sh
source common.sh
source ocp_install_env.sh

# Note This logic will likely run in a container (on the bootstrap VM)
# for the final solution, but for now we'll prototype the workflow here
export OS_TOKEN=fake-token
export OS_URL=http://localhost:6385/

trap collect_info_on_failure TERM

wait_for_json ironic \
    "${OS_URL}/v1/nodes" \
    10 \
    -H "Accept: application/json" -H "Content-Type: application/json" -H "User-Agent: wait-for-json" -H "X-Auth-Token: $OS_TOKEN"

if [ $(sudo podman ps | grep -w -e "ironic$" -e "ironic-inspector$" | wc -l) != 2 ] ; then
    echo "Can't find required containers"
    exit 1
fi

mkdir ocp/tf-master
cp ocp/master.ign ocp/tf-master

cat > ocp/tf-master/main.tf <<EOF
provider "ironic" {
  "url" = "http://localhost:6385/v1"
  "microversion" = "1.50"
}
EOF

IMAGE_SOURCE="http://172.22.0.1/images/$RHCOS_IMAGE_FILENAME_LATEST"
IMAGE_CHECKSUM=$(curl http://172.22.0.1/images/$RHCOS_IMAGE_FILENAME_LATEST.md5sum)

ROOT_GB="25"

for i in $(seq 0 2); do
  master_node_to_tf $i $IMAGE_SOURCE $IMAGE_CHECKSUM $ROOT_GB $ROOT_DISK >> ocp/tf-master/main.tf
done

echo "Deploying master nodes"
pushd ocp/tf-master
export TF_LOG=debug
terraform init
terraform apply --auto-approve
popd

echo "Master nodes active"

NUM_LEASES=$(sudo virsh net-dhcp-leases baremetal | grep master | wc -l)
while [ "$NUM_LEASES" -ne 3 ]; do
  sleep 10
  NUM_LEASES=$(sudo virsh net-dhcp-leases baremetal | grep master | wc -l)
done

echo "Master nodes up, you can ssh to the following IPs with core@<IP>"
sudo virsh net-dhcp-leases baremetal

# Wait for nodes to appear and become ready
until oc --config ocp/auth/kubeconfig get nodes; do sleep 5; done
NUM_NODES=$(oc --config ocp/auth/kubeconfig get nodes --no-headers | wc -l)
while [ "$NUM_NODES" -ne 3 ]; do
  sleep 10
  NUM_NODES=$(oc --config ocp/auth/kubeconfig get nodes --no-headers | wc -l)
done
for i in $(seq 0 2); do
  oc wait nodes/master-$i --for condition=ready --timeout=600s
done

wait_for_bootstrap_event

# disable NoSchedule taints for masters until we have workers deployed
for num in 0 1 2; do
  oc adm taint nodes master-${num} node-role.kubernetes.io/master:NoSchedule-
done

#Verify Ingress controller functionality
echo "Verifying Ingress controller functionality, first we'll check that router pod responsive"
until curl -o /dev/null -kLs --fail  tst.apps.${CLUSTER_DOMAIN}:1936/healthz; do sleep 20 && echo "Router pod not responding"; done

echo "Create service named tst-svc"
oc --config ocp/auth/kubeconfig  run --image=kuryr/demo  tst-svc
oc --config ocp/auth/kubeconfig   scale dc/tst-svc  --replicas=2
oc --config ocp/auth/kubeconfig    expose dc/tst-svc --port 1234 --target-port 8080
echo "Create unsecured route pointing to tst-svc"
oc --config ocp/auth/kubeconfig expose svc/tst-svc --hostname=www.example.com

echo "Check connectivity via Ingress controller"
until curl -o /dev/null -kLs --fail  --header 'Host: www.example.com'  tst.apps.${CLUSTER_DOMAIN}; do sleep 10 && echo "rechecking"; done
echo "Ingress controller is working!"

echo "Cluster up, you can interact with it via oc --config ocp/auth/kubeconfig <command>"
