# Agent based installer environment

This folder contains all the files and assets required to deploy a cluster
using the agent-based installer approach.

# Quickstart

Use the following configuration in your `config_<user>.sh` to deploy a 
compact cluster:

    # Configure ipv4 environment
    export IP_STACK=v4
    export NETWORK_TYPE=OpenShiftSDN

    # Configure master nodes specs
    export MASTER_DISK=120
    export MASTER_MEMORY=16384

    # In compact scenario, no workers are required
    export NUM_WORKERS=0

    # Configure e2e test scenario
    export AGENT_E2E_TEST_SCENARIO=COMPACT_IPV4

Then run the `agent` target:

    $ make agent

# Agent flow steps

| No | Step | Description | Agent specific? |
|---|---|---|---|
| 01 | requirements | Installs all the required software and dependencies | no |
| 02 | configure | Setup the network and VMs as per the specified configuration | no |
| 03 | agent_build_installer | Builds (or extract from the release payload) the openshift installer | yes |
| 04 | agent_configure | Further network customization and agent manifests creation (stored in `OCP_DIR`)  | yes |
| 05 | agent_create_cluster | Generates the agent image using openshift installer and boots the VM | yes |
| - | agent_cleanup | Deletes the agent manifests and images | yes | 

# Agent artifacts

Agent artifacts are stored in the `OCP_DIR` folder, located in the current dev-scripts checkout

# Usage scenarios

It's possible to use dev-scripts for different scenarios / goals, and the following section will describe
the recommended configurations through some concrete examples.

| Recommended scenario | Configuration | Notes |
| --- | --- | --- |
| dev | `KNI_INSTALL_FROM_GIT=true`<br>`OPENSHIFT_INSTALL_PATH=~/git/installer` | Useful for testing while developing a new feature, using an already existing local checkout |
| qe | `KNI_INSTALL_FROM_GIT=true`<br>`INSTALLER_REPO_PR=5891` | Recommended for testing a PR if the installer sources are _not_ locally available<br> (repo will be checked out in `~/go/src/github.com/openshift/installer`) |
| qe | `KNI_INSTALL_FROM_GIT=true` | As the previous case, but focusing on the latest sources available |
| dev/qe |  | In this case the latest _nightly_ release is automatically downloaded, and the installer is extracted<br>from that payload. `OPENSHIFT_RELEASE_STREAM` and `OPENSHIFT_RELEASE_TYPE` respectively<br>are used to determine the version and stream to be gathered |
| dev/qe | `OPENSHIFT_RELEASE_IMAGE=`<br>`registry.ci.openshift.org/ocp/release:4.11.0-0.nightly-2022-05-11-054135` | As before, but pinning to a specific release version |
| CI | `OPENSHIFT_RELEASE_IMAGE=<ephemeral payload pullspec>`<br>`OPENSHIFT_CI=true` | This is the configuration used in the CI to test an ephemeral payload |
