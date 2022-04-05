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

Then run the `agent` target:

    $ make agent
