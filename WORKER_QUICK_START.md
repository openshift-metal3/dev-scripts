# Quick Start: Adding Workers Post-Installation

## TL;DR

Add a worker node after your cluster is already deployed:

```bash
# Add a worker
./add_worker_node.sh my-worker-1

# Apply the generated manifest
oc apply -f ocp/ostest/my-worker-1_bmh.yaml

# Auto-approve CSRs in background
./auto_approve_csrs.sh 30 &

# Scale up your machineset
oc get machineset -n openshift-machine-api
oc scale machineset <your-cluster>-worker-0 --replicas=<N+1> -n openshift-machine-api

# Watch it join
oc get nodes -w
```

## Customizing Resources

```bash
export EXTRA_WORKER_MEMORY=32768  # 32GB RAM
export EXTRA_WORKER_DISK=100      # 100GB disk
export EXTRA_WORKER_VCPU=16       # 16 vCPUs

./add_worker_node.sh my-large-worker
```

## Using Make

```bash
# Add worker
make add_worker WORKER_NAME=worker-1

# Remove worker
make remove_worker WORKER_NAME=worker-1
```

## What Gets Created

- ✅ Libvirt VM with specified resources
- ✅ Virtual BMC (IPMI or Redfish)
- ✅ BareMetalHost manifest
- ✅ Secret for BMC credentials
- ✅ Complete setup instructions

## Removing a Worker

```bash
# Remove from cluster and delete VM
./remove_worker_node.sh my-worker-1

# Don't forget to scale down the machineset
oc scale machineset <your-cluster>-worker-0 --replicas=<N-1> -n openshift-machine-api
```

## Full Documentation

See [docs/add-worker-post-install.md](docs/add-worker-post-install.md) for detailed documentation.

