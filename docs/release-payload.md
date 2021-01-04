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
$ oc adm release info registry.ci.openshift.org/ocp/release:4.2 | grep baremetal-installer
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
