# Using Custom Machine API Operator and Actuator

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

Tell cluster-version-operator to stop managing the machine-api-operator's
Deployment. Without this, it will scale the MAO back up within a few minutes of
you scaling it down.

```sh
oc patch clusterversion version --namespace openshift-cluster-version --type merge -p '{"spec":{"overrides":[{"kind":"Deployment","name":"machine-api-operator","namespace":"openshift-machine-api","unmanaged":true}]}}'
```

Stop the currently running MAO by scaling it to zero replicas:

```sh
oc scale deployment -n openshift-machine-api --replicas=0 machine-api-operator
```

## 3) Stop the cluster-api controllers

The MAO probably started a set of cluster-api controllers that need to be
stopped, as well:

```sh
oc delete deployment -n openshift-machine-api clusterapi-manager-controllers
```

## 4) Prepare the MAO to run locally

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

## 5) Prepare a custom build of CAPBM

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

## 6) Now run the MAO

Before running the MAO, we have to undo the change we did earlier by asking the
cluster-version-operator to manage the machine-api-operator's deployment again.
Without this, it will not scale the MAO back up.

```sh
oc patch clusterversion version --namespace openshift-cluster-version --type merge -p '{"spec":{"overrides":[{"kind":"Deployment","name":"machine-api-operator","namespace":"openshift-machine-api","unmanaged":false}]}}'
```

Change `custom-images.json` to `pkg/operator/fixtures/images.json` if you
didn’t build a custom CAPBM.

Update the `kubeconfig` path to reflect your own environment.

```sh
bin/machine-api-operator start --images-json=custom-images.json --kubeconfig=/home/${USER}/dev-scripts/ocp/auth/kubeconfig -v 4
```
