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
oc delete deployment -n openshift-machine-api machine-api-controllers
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
bin/machine-api-operator start --images-json=custom-images.json --kubeconfig=/home/${USER}/dev-scripts/ocp/$CLUSTER_NAME/auth/kubeconfig -v 4
```

## Run baremetal-operator from local source checkout

metal3 relies on ironic, a database, and other services that normally
run inside the cluster. These can be launched with the script
"metal3-dev/local-bmo.sh". The script stops the machine-api-operator,
scales down the Deployment containing the services related to the
baremetal-operator, and creates a new Deployment called
"metal3-development" containing everything the baremetal-operator
relies on. Finally, it uses the source in
`$GOPATH/github.com/metal3-io/baremetal-operator` to build and run a
version of the baremetal-operator from source, including updating the
CRD for the BareMetalHost.

```sh
./metal3-dev/local-bmo.sh
```

To restore the version of the baremetal-operator deployed with the
cluster, run

```sh
./metal3-dev/mao-bmo.sh
```

## Run cluster-api-provider-baremetal from local source checkout

The cluster API provider component is part of a Pod created by the
machine-api-operator. The same Pod runs several other components which
must be running for the cluster to function properly. The script

"metal3-dev/local-capbm.sh". The script stops the
machine-api-operator, scales down the Deployment it created, and
creates a new Deployment called "capbm-development" containing
everything the old Deployment contained except for the
cluster-api-provider-baremetal. Finally, it runs `make run` in
`$GOPATH/github.com/openshift/cluster-api-provider-baremetal` to build
and run a version of CAPBM from source.

```sh
./metal3-dev/local-capbm.sh
```

To restore the version of CAPBM deployed with the cluster, run

```sh
./metal3-dev/mao-capbm.sh
```
