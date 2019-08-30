# Using Custom Machine API Operator and Actuator or Baremetal Operator

This document shows how to run a custom build of both the machine-api-operator
(MAO) and the BareMetal Machine actuator, cluster-api-provider-baremetal
(CAPBM).

This is helpful if you want to try some changes not in the current release
image.  You can check with a command like:

```sh
oc adm release info registry.svc.ci.openshift.org/openshift/origin-release:v4.0 --commits | grep baremetal
```

## 1) Launch a cluster as usual

It’s assumed that you start by bringing up a cluster as usual.

## 2) Stop the MAO

The cluster-version-operator needs to be told to stop managing the
machine-api-operator's Deployment. Without this, it will scale the MAO
back up within a few minutes of you scaling it down.

Then the deployment running the machine-api-operator needs to be
scaled down to stop the service.

Both of these steps are handled by the "stop-mao.sh" script.

```sh
./stop-mao.sh
```

## Run a custom cluster-api provider

If you want to run a custom version of the
cluster-api-provider-baremetal (CAPB or "actuator"), you need to
disable the version the machine-api-operator started. You do not need
to follow this step if you are only going to run a custom version of
the baremetal-operator.

### 1) Stop the cluster-api controllers

```sh
oc delete deployment -n openshift-machine-api clusterapi-manager-controllers
```

### 2) Prepare the MAO to run locally

```sh
git clone https://github.com/openshift/machine-api-operator
cd machine-api-operator
# Make any necessary changes
make machine-api-operator
```

If you have trouble building the MAO with the above command, you can try
running podman manually.  Fix the paths to reflect your environment, first.

```sh
sudo podman run --rm -v "/home/${USER}/go/src/github.com/openshift/machine-api-operator":/go/src/github.com/openshift/machine-api-operator:Z -w /go/src/github.com/openshift/machine-api-operator golang:1.10 ./hack/go-build.sh machine-api-operator
```

### 3) Prepare a custom build of CAPBM

This step is only needed if you want to run a custom build of the actuator, and
not just a custom build of the MAO.

```sh
cd ..
git clone https://github.com/openshift/cluster-api-provider-baremetal
cd cluster-api-provider-baremetal
# Make necessary changes
podman build -t quay.io/username/origin-baremetal-machine-controllers .
podman login quay.io
podman push quay.io/username/origin-baremetal-machine-controllers
```

After building your custom CAPBM image, you will need to create a custom images
file for the MAO to use.

```sh
cd ../machine-api-operator
cp pkg/operator/fixtures/images.json custom-images.json
```

Edit `custom-images.json` to have a modified image for the BareMetal case:

```
{
  "clusterAPIControllerAWS": "docker.io/openshift/origin-aws-machine-controllers:v4.0.0",
  "clusterAPIControllerOpenStack": "docker.io/openshift/origin-openstack-machine-controllers:v4.0.0",
  "clusterAPIControllerLibvirt": "docker.io/openshift/origin-libvirt-machine-controllers:v4.0.0",
  "machineAPIOperator": "docker.io/openshift/origin-machine-api-operator:v4.0.0",
  "clusterAPIControllerBareMetal": "quay.io/openshift-metalkube/origin-baremetal-machine-controllers:latest",
  "clusterAPIControllerAzure": "quay.io/openshift/origin-azure-machine-controllers:v4.0.0"
}
```

### 4) Now run the MAO

Change `custom-images.json` to `pkg/operator/fixtures/images.json` if you
didn’t build a custom CAPBM.

Update the `kubeconfig` path to reflect your own environment.

```sh
bin/machine-api-operator start --images-json=custom-images.json --kubeconfig=/home/${USER}/dev-scripts/ocp/auth/kubeconfig -v 4
```

## Run a custom baremetal-operator

This step assumes that the machine-api-operator has been completely
stopped, as described above, so that it does not re-deploy metal3 and
break the manual configuration performed below.

### 1) Remove the metal3 deployment

The machine-api-provider creates a "metal3" deployment, which needs to
be deleted.

```sh
oc delete deployment -n openshift-machine-api metal3
```

### 2) Launch the metal3 support services in the cluster

metal3 relies on ironic, a database, and other services that normally
run inside the cluster. These can be launched with the script
"metal3-dev/run.sh". The script creates a Deployment called
"metal3-development" to differentiate it from the standard "metal3"
deployment.

```sh
./metal3-dev/run.sh
```
