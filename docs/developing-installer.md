# Developing openshift-install

In the normal workflow, dev-scripts extracts the installer binary out of
a [release image](release-payload.md).  If you would like to develop and
test changes to openshift-install locally, set the `KNI_INSTALL_FROM_GIT`
environment variable:

```console
$ KNI_INSTALL_FROM_GIT=true make
```

If you have a copy of the installer already in
`$GOPATH/src/github.com/openshift/installer`, it will build
on whatever branch you currently have checked out. If there is not
already a checkout of the installer, it will clone the repo from GitHub
and build from the master branch.
