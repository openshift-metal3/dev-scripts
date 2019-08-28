# Baremetal installer in OpenShift releases

OpenShift publishes a release payload image which includes information
about cluster operator images and their resource manifests, along with
references to installer and CLI images. The recommended method for
obtaining an installer binary is to first choose a release version and
then use the `oc adm release extract` command to extract the installer
binary from the release payload.

Since 4.2, an image named `baremetal-installer` is included with each
release payload, which contains an openshift-installer compiled by with
the `baremetal` and `libvirt` build tags.

```sh
$ oc adm release info registry.svc.ci.openshift.org/ocp/release:4.2 | grep baremetal-installer
baremetal-installer  sha256:fa2c82f8d88d375f048b8da6fc823ffc8a99da4560e7478bc6a63f83f6721ca3
```

This image is included in each release via a reference in the
[cluster-samples-operator](https://github.com/openshift/cluster-samples-operator/blob/ee4165c89d53119e541fe9b8141d01cab7207560/manifests/image-references#L17-L20).
It gets built from a [Dockerfile](https://github.com/openshift/installer/blob/master/images/baremetal/Dockerfile.ci) in the installer repo.

## Extracting the openshift-install binary

To extract the openshift-install binary that includes support for the
baremetal IPI platform, you can use the `oc adm release extract`
commands. Note that openshift-baremetal-installer is optional, and isn't
included when extracting all tools with the `--tools` option; it must be
explicitly stated.

To get just the binary:

```
oc adm release extract --registry-config <pull secret> --command=openshift-baremetal-install --to /tmp
```

To get a tarball:

```
oc adm release extract --registry-config <pull secret> --command=openshift-baremetal-install --command-os='*' --to /tmp
```

# Building a custom release

Occassionally, it may be neccessary to build a custom release payload,
that includes changes to the installer, or other images such as Ironic.
You may use the `kni` workspace in OpenShift CI to do this.  Be aware,
that CI releases are garbage collected after a period of time, and in
order to avoid this happening you must ask ART to pin the CI or nightly
release you are using to base your custom payload on.

## Preparation and Configuration

We build and publish within a namespace on an OpenShift
cluster. First, prepare a `kubeconfig` with credentials to this
cluster, and with the desired namespace set as the default:

```
$ oc --config=release-kubeconfig login https://api.ci.openshift.org --token=...
$ oc --config=release-kubeconfig new-project kni
$ oc --config=release-kubeconfig project kni
$ oc --config=release-kubeconfig adm policy add-role-to-user admin <other admin>
````

We need a docker registry credentials file which contains credentials
for the registry on this OpenShift cluster:

```
$ oc --config=release-kubeconfig registry login --to=release-pullsecret
```

But also, we need credentials for any registry hosting images
referenced from release payloads (e.g. ```quay.io```)

```
$ TOKEN=$((. ../config_$USER.sh && echo $PULL_SECRET) 2>/dev/null | jq -r '.auths["quay.io"].auth' | base64 -d)
$ podman login --authfile=release-pullsecret -u ${TOKEN%:*} -p ${TOKEN#*:} quay.io
```

Images are published to imagestream tags, and we need an image stream
for our installer builds and our custom release payloads:

```
$ oc --config=release-kubeconfig create imagestream release
$ oc --config=release-kubeconfig create imagestream baremetal-installer
```

We need to create a ```docker-registry``` secret so the image stream
can import referenced images:

```
$ oc --config=release-kubeconfig \
    create secret docker-registry quay-pullsecret \
    --docker-server=quay.io \
    --docker-username=${TOKEN%:*} \
    --docker-password=${TOKEN#*:}
```

Finally, create a ```release_config_$USER.sh``` file with information
about all of the above:

```
$ cat > release_config_$USER.sh <<EOF
RELEASE_NAMESPACE=kni
RELEASE_STREAM=release
INSTALLER_STREAM=baremetal-installer
RELEASE_KUBECONFIG=release-kubeconfig
RELEASE_PULLSECRET=release-pullsecret
INSTALLER_GIT_URI=https://github.com/openshift/installer.git
INSTALLER_GIT_REF=master
EOF
```

## Building an Installer

If you want to build a custom installer with your changes, update the
`INSTALLER_GIT_URI` and `INSTALLER_GIT_REF` parameters in your
`release_config_$USER.sh`, and use the build-installer script.

Find the most recent CI release that's green from [the release
dashboard](https://openshift-release.svc.ci.openshift.org/), then
build an installer image with the baremetal platform enabled:

```
$ ./build_installer.sh 4.2.0-0.ci-2019-08-21-085721-kni.0
```

## Building a release payload

Now, finally, we can build a new payload referencing our installer,
and tag it into the release imagestream:

```
$ ./prep_release.sh \
    4.2.0-0.ci-2019-08-21-085721-kni.0 \
    registry.svc.ci.openshift.org/ocp/release:4.2.0-0.ci-2019-08-21-085721 \
    baremetal-installer=registry.svc.ci.openshift.org/kni/baremetal-installer:4.2.0-0.ci-2019-08-21-085721-kni.0 \
    baremetal-machine-controllers=quay.io/openshift-metal3/baremetal-machine-controllers@sha256:1faf4a863b261c948f5f38c148421603f51c74cbf44142882826ee6cb37d8bd3
```
