# Custom release payload

In some circumstances it could be helpful for the developer to deploy a cluster by using a slightly
modified OpenShift release payload: for example, to test/verify some local changes before pushing them in branch or PR.
In particular, especially when working in the agent scenario, it's not unusual that a new feature/bugfix may
span across several images.

Dev-scripts offers a mechanism to easily prepare a local ephemeral release payload, containing a copy
of all the images of a given release, overridden by those ones that have been modified locally. The custom
release payload, as well as the custom images, are stored in a local registry managed by dev-scripts.

> [!NOTE]
> In the agent worklow (`make agent`) this mechanism is provided by the Makefile goal `agent_prepare_release`.

# Prepare the environment

The first step consists in having a local checkout of all the repos that are meant to be used for the release
(see in the appendix for the specific agent repos and image names), with the desired code changes.
Even though not strictly necessary, it's recommended to manually build each Dockerfile to ensure that it's working fine.

# Configure the local repositories

For every repository meant to replace an image entry in the release payload, a new configuration variable is required in 
`config_<user>.sh`, in the following form:

``` bash
export <ENTRYNAME>_LOCAL_REPO=<repo location>
```

Where:
* `<ENTRYNAME>` is a key string representing the name of the repository (and associated release image)
* `<repo location>` is the path of a previously cloned repostiory

For example, the following configuration replaces the `agent-installer-utils` image:

``` bash
export AGENT_INSTALLER_UTILS_LOCAL_REPO=~/git/agent-installer-utils
```

It's sufficient to define at least one `<ENTRYNAME>_LOCAL_REPO` config variable for enabling the step to prepare a local release.

# Image build process

By default, the step looks for a `Dockerfile.ocp` or `Dockerfile` within each configured repo folder for building the new images.
Every image is then built and pushed into the local registry, stored under the `/localimages/<ENTRYNAME>` path. 
The previous example produces the following registry content (using the default dev-scripts registry vars):

``` bash
$ curl -s -u ocp-user:ocp-pass https://virthost.ostest.test.metalkube.org:5000/v2/_catalog | jq -r
{
  "repositories": [
    "localimages/agent-installer-utils",
    "localimages/local-release-image"
  ]
}
```

> [!NOTE]
> The `/localimages/local-release-image` contains all the tags of the currently used OpenShift release payload

The step takes care to replace the old `<ENTRYNAME>` image digest with the new image reference to the local registry, by updating
the `release-manifests/image-references` file within the main release payload image.

More precisely, after all the configured repos images have been built, a new release image (containing all the images overrides) is 
finally built and pushed into `"localimages/local-release-image`, to replace the previous one.

## Specify a Dockerfile

Since there's not a common standard about the Dockerfile location - and file name, the `<ENTRYNAME>_DOCKERFILE` configuration variable can be used to 
specify how to retrieve it within the repo folder. For example:

``` bash
export ASSISTED_SERVICE_LOCAL_REPO=~/git/assisted-service
export ASSISTED_SERVICE_DOCKERFILE=Dockerfile.assisted-service.ocp
```

> [!NOTE]
> The `<ENTRYNAME>` prefix must match an already existing `<ENTRYNAME>_LOCAL_REPO`

## Specify an image name

By default, for a given repo the associated image name is equal to the (sanitized) prefix `<ENTRYNAME>` used in the config vars: for example, the
`INSTALLER_REPO_LOCAL` variable will produce an `installer` image. Anyhow, in some cases the name of the image within the release payload is 
different from the repo name. For that, it's possible to specify the image name that will be used for the replacement, through the `<ENTRYNAME>_IMAGE` var:

``` bash
export ASSISTED_SERVICE_LOCAL_REPO=~/git/assisted-service
export ASSISTED_SERVICE_DOCKERFILE=Dockerfile.assisted-service.ocp
export ASSISTED_SERVICE_IMAGE=agent-installer-api-server
```

The previous example will build a new image using the `Dockerfile.assisted-service.ocp` found in `~/git/assisted-service`, it will be stored at
`virthost.ostest.test.metalkube.org:5000/localimages/assisted-service:latest` and it will be used as `agent-installer-api-server` within the newly
built release image.

## Specify an image build arg

It may also be useful to configure an additional build arg when building an image. The `<ENTRYNAME>_BUILD_ARG` could be 
use for that:

``` bash
export INSTALLER_BAREMETAL_LOCAL_REPO=~git/installer
export INSTALLER_BAREMETAL_DOCKERFILE=images/baremetal/Dockerfile.ci
export INSTALLER_BAREMETAL_IMAGE=baremetal-installer
export INSTALLER_BAREMETAL_BUILD_ARG="TAGS=\"okd libvirt baremetal\""
```

# Clean up

To remove the local registry, and all of its content, use `make realclean`.

# Appendix

## Agent repos

| Image name | OCP Repo | Dockerfile |
| --- | --- | --- |
| agent-installer-api-server | https://github.com/openshift/assisted-service | Dockerfile.assisted-service.ocp |
| agent-installer-csr-approver | https://github.com/openshift/assisted-installer | Dockerfile.assisted-installer-controller.ocp |
| agent-installer-orchestrator | https://github.com/openshift/assisted-installer | Dockerfile.assisted-installer.ocp |
| agent-installer-node-agent | https://github.com/openshift/assisted-installer-agent | Dockerfile.ocp |
| agent-installer-utils | https://github.com/openshift/agent-installer-utils | Dockerfile.ocp |
| agent-installer-web-ui | https://github.com/openshift-assisted/assisted-installer-ui | https://github.com/openshift-assisted/assisted-installer-ui/blob/master/apps/assisted-disconnected-ui/Containerfile.ocp |
| agent-installer-console| https://github.com/openshift-assisted/assisted-installer-ui | https://github.com/openshift-assisted/assisted-installer-ui/blob/master/apps/assisted-disconnected-ui/Containerfile.ocp |
| agent-installer-web-console| https://github.com/openshift-assisted/assisted-installer-ui | https://github.com/openshift-assisted/assisted-installer-ui/blob/master/apps/assisted-disconnected-ui/Containerfile.ocp |


## Installer exception

Dev-scripts offers a dedicated configuration variable for testing a local installer repo: 

``` bash
export KNI_INSTALL_FROM_GIT=true
```

Such variable allows using a local installer repo (stored in the path pointed by `$OPENSHIFT_INSTALL_PATH` - by default 
equal `$GOPATH/src/github.com/openshift/installer`) to build an installer binary that will be used to deploy the cluster.
This mechanism is orthogonal to the local release build process, and it may be recommended when developing/testing just the installer,
since it does not require to setup a local registry (resulting then in faster deploy).
