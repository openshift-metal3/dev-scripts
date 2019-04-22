# Publishing a KNI Release Payload

OpenShift publishes a release payload image which includes information
about cluster operator images and their resource manifests, along with
references to installer and CLI images. The recommended method for
obtaining an installer binary is to first choose a release version and
then use the `oc adm release extract --tools` command to extract the
installer binary from the release payload.

Since KNI has temporarily forked the installer, we build custom and
publish custom release payloads that include a reference to the forked
installer.

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
$ oc --config=release-kubeconfig create imagestream installer
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
INSTALLER_STREAM=installer
RELEASE_KUBECONFIG=release-kubeconfig
RELEASE_PULLSECRET=release-pullsecret
INSTALLER_GIT_URI=https://github.com/openshift-metal3/kni-installer.git
INSTALLER_GIT_REF=master
EOF
```

## Building an Installer and Payload

When we want to move to a newer OpenShift release, we pick a release
payload:

```
$ oc adm release info registry.svc.ci.openshift.org/ocp/release:4.0.0-0.ci-2019-04-17-133604 -a release-pullsecret -o json | jq -r .metadata.version
4.0.0-0.ci-2019-04-17-133604
```

Next, rebase ```openshift-metal3/kni-installer``` to the
```openshift/installer``` commit referenced by that payload:

```
$ oc adm release info -a release-pullsecret -o json \
    registry.svc.ci.openshift.org/ocp/release:4.0.0-0.ci-2019-04-17-133604 \
    jq -r '.references.spec.tags[] | select(.name == "installer") | .annotations["io.openshift.build.commit.id"]'
8c607f66662f8e35570960484612d0589c26b654
```

And then kick off a build, with the resulting image tagged into the
installer image stream using the supplied version as the tag:

```
$ ./build_installer.sh 4.0.0-0.ci-2019-04-17-133604
```

Now, finally, we can build a new payload referencing our installer,
and tag it into the release imagestream:

```
$ ./prep_release.sh \
    registry.svc.ci.openshift.org/ocp/release:4.0.0-0.ci-2019-04-17-133604 \
    registry.svc.ci.openshift.org/kni/installer:4.0.0-0.ci-2019-04-17-133604
```
