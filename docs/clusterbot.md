How to use Cluster Bot builds with dev-scripts
==============================================

*Cluster Bot is a Slack app that can help you develop, and test OpenShift
clusters.  If you're new to Cluster Bot, you can say "help" to it, and it will
show you what it can do.*

One of the cool features of Cluster Bot is that it can build a release image
based on one or more unmerged pull requests.  The image can then be plugged into
dev-scripts, and a new cluster created with that image.

First, to build your image, say something like this to Cluster Bot:

    build openshift/cluster-api-provider-baremetal#166

In a few minutes, the bot replies with a link.  Open it, and then view the raw
build log.

Near the end it will say something like:

```
Creating release image registry.build01.ci.openshift.org/ci-ln-1kn6smt/release:latest
```

In your `config_$USER.sh` file, set the value of `OPENSHIFT_RELEASE_IMAGE` to
the above image like this:

```
export OPENSHIFT_RELEASE_IMAGE=registry.build01.ci.openshift.org/ci-ln-1kn6smt/release:latest
```

Near the bottom of the build log, you'll also find a link to the console.  It
looks something like this:

```
https://console.build01.ci.openshift.org/k8s/cluster/projects/ci-ln-1kn6smt
```

Open the link, and log in. In the upper right corner, select Copy login command.

Put the token into `CI_TOKEN` in your `config_$USER.sh`.  Make sure it appears
after your regular token if you've used one previously.

Before you close the login window, note the URL of the CI server, for me it's always:

```
curl -H "Authorization: Bearer sha256~xxxxxxxxxxxxx" \
    "https://api.build01.ci.devcluster.openshift.com:6443/apis/user.openshift.io/v1/users/~"
```

And in your `config_$USER.sh`, say:

```
export CI_SERVER=api.build01.ci.devcluster.openshift.com
```

Then, you are ready to build your cluster as usual with `make`.
