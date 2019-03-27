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

# Wait for master nodes to have a DNS record. The DNS service is binding on all
# interfaces so we can query the API VIP to retrieve the records
NUM_MASTERS=$(dig +short SRV @api.${CLUSTER_DOMAIN} _etcd-server-ssl._tcp.${CLUSTER_DOMAIN} | wc -l)
while [ "$NUM_MASTERS" -ne 3 ]; do
  sleep 10
  NUM_MASTERS=$(dig +short SRV @api.${CLUSTER_DOMAIN} _etcd-server-ssl._tcp.${CLUSTER_DOMAIN} | wc -l)
done

for etcd in $(dig +short SRV @api.${CLUSTER_DOMAIN} _etcd-server-ssl._tcp.${CLUSTER_DOMAIN} | awk '{print $NF}'); do
  MASTER_NAME=$(dig +short CNAME @api.${CLUSTER_DOMAIN} $etcd | head -1)
  MASTER_IP=$(dig +short CNAME @api.${CLUSTER_DOMAIN} $etcd | tail -1)
  echo "You can ssh to $MASTER_NAME with core@$MASTER_IP"
done

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
  oc label node master-${num} node-role.kubernetes.io/worker=''
done

echo "Cluster up, you can interact with it via oc --config ocp/auth/kubeconfig <command>"
