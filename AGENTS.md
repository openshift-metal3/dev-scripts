# OpenShift Dev Scripts Guide

## Introduction

The `dev-scripts` repository provides a comprehensive set of scripts and automation for deploying OpenShift on baremetal infrastructure, with a focus on development, testing, and CI/CD workflows. It supports multiple deployment methods including traditional IPI (Installer Provisioned Infrastructure) using Ironic, and Agent-based installation.

The project is primarily designed for:
- **Development**: Testing OpenShift features and components locally
- **CI/CD**: Automated testing in OpenShift CI pipelines
- **Baremetal Testing**: Simulating baremetal deployments using libvirt VMs
- **Edge Scenarios**: Testing Single Node OpenShift (SNO) and compact clusters

## Repository Structure

```
dev-scripts/
├── 01_install_requirements.sh       # Install system dependencies
├── 02_configure_host.sh             # Configure host networking and VMs
├── 03_build_installer.sh            # Extract openshift-install binary
├── 04_setup_ironic.sh               # Setup Ironic containers
├── 05_create_install_config.sh      # Generate install-config.yaml
├── 06_create_cluster.sh             # Deploy the cluster
│
├── agent/                           # Agent-based installation scripts
│   ├── 01_agent_requirements.sh
│   ├── 03_agent_build_installer.sh
│   ├── 04_agent_prepare_release.sh
│   ├── 05_agent_configure.sh
│   ├── 06_agent_create_cluster.sh
│   ├── 07_agent_add_extraworker_nodes.sh
│   └── docs/                        # Agent-specific documentation
│
├── assets/                          # Configuration templates and patches
├── metal3-dev/                      # Metal3 development utilities
├── metallb/                         # MetalLB deployment scripts
├── network-configs/                 # Network configuration examples
│   ├── bond/                        # Bonded network configs
│   ├── static/                      # Static IP configs
│   └── nmstate-brex-bond/           # NMState configs
│
├── docs/                            # Additional documentation
├── config_example.sh                # Comprehensive configuration examples
├── common.sh                        # Shared functions and utilities
├── Makefile                         # Main automation entry point
└── README.md                        # Primary documentation
```

## General Workflow

The deployment follows a sequential workflow through six main steps:

### Step 01: Install Requirements
**Script**: `01_install_requirements.sh`

Installs all prerequisite packages and tools:
- System packages (libvirt, podman, ansible, etc.)
- OpenShift client tools (`oc`, `kubectl`)
- Development tools (Go, yq, jq)
- Starts local container registry (if `ENABLE_LOCAL_REGISTRY=true`)

**Key Environment Variables**:
- `ANSIBLE_VERSION`: Override Ansible version
- `GO_VERSION`: Override Go version
- `OPENSHIFT_CLIENT_TOOLS_URL`: Custom oc/kubectl download URL

### Step 02: Configure Host
**Script**: `02_configure_host.sh`

Configures the host environment:
- Creates libvirt networks (`baremetal`, `provisioning`)
- Configures firewall rules and NAT
- Creates virtual BMC nodes for testing
- Sets up networking bridges
- Generates SSH keys if needed
- Configures NTP/chronyd

**Key Environment Variables**:
- `WORKING_DIR`: Base directory for all operations (default: `/opt/dev-scripts`)
- `CLUSTER_NAME`: OpenShift cluster name (default: `ostest`)
- `NUM_MASTERS`: Number of control plane nodes (default: `3`)
- `NUM_WORKERS`: Number of worker nodes (default: `2`)

### Step 03: Build Installer
**Script**: `03_build_installer.sh`

Extracts the `openshift-install` binary from the release payload:
- Downloads the specified OCP release image
- Extracts `openshift-install` tool
- Caches the installer for reuse

**Key Environment Variables**:
- `OPENSHIFT_RELEASE_IMAGE`: Specific release image to deploy
- `OPENSHIFT_RELEASE_STREAM`: Release stream (e.g., `4.21`)
- `OPENSHIFT_RELEASE_TYPE`: Release type (`nightly`, `ci`, `ga`, `okd`)

### Step 04: Setup Ironic
**Script**: `04_setup_ironic.sh`

Deploys Ironic baremetal provisioning services:
- Starts Ironic containers (ironic, ironic-inspector, httpd, mariadb)
- Configures DHCP and TFTP services
- Sets up image caching
- Prepares provisioning network

**Note**: This step is only used for traditional IPI installations, not for Agent-based installations.

### Step 05: Create Install Config
**Script**: `05_create_install_config.sh`

Generates the `install-config.yaml`:
- Configures cluster networking (IPv4/IPv6/dual-stack)
- Sets up node definitions and BMC credentials
- Configures pull secrets and SSH keys
- Applies customizations from environment variables

**Key Environment Variables**:
- `IP_STACK`: IP configuration (`v4`, `v6`, `v4v6`, `v6v4`)
- `BASE_DOMAIN`: Cluster base domain
- `FIPS_MODE`: Enable FIPS compliance
- `NETWORK_TYPE`: CNI plugin (`OVNKubernetes`, `OpenShiftSDN`)

### Step 06: Create Cluster
**Script**: `06_create_cluster.sh`

Deploys the OpenShift cluster:
- Runs `openshift-install create cluster`
- Monitors installation progress
- Generates `kubeconfig` and `clouds.yaml`
- Performs post-installation validation
- Creates cluster credentials

**Key Environment Variables**:
- `OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE`: Override release image
- `CI_TOKEN`: OpenShift CI authentication token

## Configuration Examples

Below are four common deployment scenarios. Create a `config.sh` file in the repository root with your desired configuration.

### Scenario 1: IPv4 Single Stack - Minimal Development Cluster

Ideal for local development with minimal resource requirements.

```bash
#!/bin/bash
# Minimal IPv4 cluster for development

# Authentication (required)
export CI_TOKEN='your-token-here'

# Basic cluster configuration
export CLUSTER_NAME="dev"
export BASE_DOMAIN="test.metalkube.org"
export WORKING_DIR="/home/dev-scripts"

# Single stack IPv4
export IP_STACK="v4"
export HOST_IP_STACK="v4"

# Minimal node configuration
export NUM_MASTERS=3
export NUM_WORKERS=0  # Compact cluster (no workers)

# Reduced VM resources for laptops
export MASTER_MEMORY=12288  # 12GB per master
export MASTER_DISK=50       # 50GB disk
export MASTER_VCPU=4        # 4 vCPUs

# Use latest nightly build
export OPENSHIFT_RELEASE_STREAM="4.21"
export OPENSHIFT_RELEASE_TYPE="nightly"

# Enable local registry for faster deployments
export ENABLE_LOCAL_REGISTRY=true
export MIRROR_IMAGES=true
```

### Scenario 2: IPv6 Dual Stack - Production-Like Testing

Simulates production environment with dual-stack networking.

```bash
#!/bin/bash
# Production-like dual-stack cluster

# Authentication
export CI_TOKEN='your-token-here'

# Cluster configuration
export CLUSTER_NAME="prod-test"
export BASE_DOMAIN="lab.example.com"
export WORKING_DIR="/opt/dev-scripts"

# Dual stack IPv6-primary
export IP_STACK="v6v4"
export HOST_IP_STACK="v4v6"

# Full HA configuration
export NUM_MASTERS=3
export NUM_WORKERS=2

# Production-like resources
export MASTER_MEMORY=16384  # 16GB
export MASTER_DISK=120      # 120GB
export MASTER_VCPU=8        # 8 vCPUs

export WORKER_MEMORY=16384
export WORKER_DISK=120
export WORKER_VCPU=8

# GA release
export OPENSHIFT_RELEASE_TYPE="ga"
export OPENSHIFT_VERSION="4.18"

# Enable features
export ENABLE_LOCAL_REGISTRY=true
export MIRROR_IMAGES=true
export FIPS_MODE=true
export ENABLE_METALLB_MODE="l2"
```

### Scenario 3: Single Node OpenShift (SNO) - Edge Computing

Perfect for edge computing scenarios or minimal footprint deployments.

```bash
#!/bin/bash
# Single Node OpenShift (SNO) configuration

# Authentication
export CI_TOKEN='your-token-here'

# Cluster configuration
export CLUSTER_NAME="edge-sno"
export BASE_DOMAIN="edge.example.com"
export WORKING_DIR="/home/sno-dev"

# IPv4 for simplicity
export IP_STACK="v4"

# SNO requires only 1 master, 0 workers
export NUM_MASTERS=1
export NUM_WORKERS=0

# SNO minimum resources
export MASTER_MEMORY=16384  # 16GB minimum for SNO
export MASTER_DISK=120      # 120GB
export MASTER_VCPU=8        # 8 vCPUs minimum

# Use Agent-based installer for SNO
# (Use agent/ scripts instead of main scripts)
export AGENT_E2E_TEST_SCENARIO="SNO_IPV4"
export AGENT_E2E_TEST_BOOT_MODE="ISO"

# Latest nightly
export OPENSHIFT_RELEASE_STREAM="4.21"
export OPENSHIFT_RELEASE_TYPE="nightly"
```

### Scenario 4: Custom Development - Testing Custom Components

For developers testing custom operators or components.

```bash
#!/bin/bash
# Custom component development environment

# Authentication
export CI_TOKEN='your-token-here'

# Cluster configuration
export CLUSTER_NAME="dev-custom"
export WORKING_DIR="/home/dev-scripts"

# IPv4 single stack
export IP_STACK="v4"

# Compact cluster
export NUM_MASTERS=3
export NUM_WORKERS=0

# Standard resources
export MASTER_MEMORY=16384
export MASTER_DISK=60
export MASTER_VCPU=8

# Local development settings
export ENABLE_LOCAL_REGISTRY=true
export MIRROR_IMAGES=true

# Custom component images
export IRONIC_LOCAL_IMAGE="https://github.com/metal3-io/ironic"
export MACHINE_CONFIG_OPERATOR_LOCAL_IMAGE="https://github.com/openshift/machine-config-operator"

# Custom MAO testing
export TEST_CUSTOM_MAO=true
export CUSTOM_MAO_IMAGE="quay.io/myuser/machine-api-operator:dev"

# Additional capabilities
export BASELINE_CAPABILITY_SET="None"
export ADDITIONAL_CAPABILITIES="baremetal,Console"

# Development tools
export INSTALL_OPERATOR_SDK=1

# Custom release
export OPENSHIFT_RELEASE_STREAM="4.21"
export OPENSHIFT_RELEASE_TYPE="nightly"
```

## Usage

### Traditional IPI Installation

```bash
# 1. Create configuration
cp config_example.sh config.sh
vim config.sh  # Edit with your settings

# 2. Run all steps via Makefile
make

# 3. Or run individual steps
./01_install_requirements.sh
./02_configure_host.sh
./03_build_installer.sh
./04_setup_ironic.sh
./05_create_install_config.sh
./06_create_cluster.sh
```

### Agent-Based Installation

```bash
# 1. Configure for agent installation
export AGENT_E2E_TEST_SCENARIO="HA_IPV4"

# 2. Run agent scripts
cd agent/
./01_agent_requirements.sh
./03_agent_build_installer.sh
./04_agent_prepare_release.sh
./05_agent_configure.sh
./06_agent_create_cluster.sh
```

### Cleanup

```bash
# Full cleanup (removes cluster and VMs)
make clean

# Individual cleanup scripts
./ocp_cleanup.sh         # Remove cluster
./host_cleanup.sh        # Remove VMs and networks
./registry_cleanup.sh    # Remove local registry
```

## Common Operations

### Accessing the Cluster

```bash
# Set KUBECONFIG
export KUBECONFIG=$(pwd)/ocp/${CLUSTER_NAME}/auth/kubeconfig

# Verify cluster access
oc get nodes
oc get co  # Check cluster operators
```

### Interacting with Ironic

```bash
# Source the clouds.yaml
export OS_CLOUD=metal3

# List baremetal nodes
openstack baremetal node list
```

### Viewing Logs

```bash
# Bootstrap logs
./show_bootstrap_log.sh

# Specific component logs
./bootstrap_ironic_log.sh
./bootstrap_bootkube_log.sh
```

## Related Documentation

### Official Documentation
- [OpenShift Documentation](https://docs.openshift.com/)
- [OpenShift Baremetal IPI](https://docs.openshift.com/container-platform/latest/installing/installing_bare_metal_ipi/ipi-install-overview.html)
- [Agent-based Installer](https://docs.openshift.com/container-platform/latest/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html)

### Project Documentation
- [README.md](README.md) - Main project documentation
- [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guidelines
- [dev-setup.md](dev-setup.md) - Development environment setup
- [agent/README.md](agent/README.md) - Agent-based installation guide
- [agent/docs/](agent/docs/) - Agent-specific documentation
  - [config-presets-and-options.md](agent/docs/config-presets-and-options.md)
  - [add-nodes.md](agent/docs/add-nodes.md)
  - [custom-release.md](agent/docs/custom-release.md)

### Specific Topics
- [Assisted Deployment](docs/assisted-deployment.md)
- [Custom MAO and CAPBM](docs/custom-mao-and-capbm.md)
- [Developing Installer](docs/developing-installer.md)
- [Release Payload](docs/release-payload.md)
- [Clusterbot Usage](docs/clusterbot.md)

### Metal3 Resources
- [Metal3.io](https://metal3.io/)
- [Baremetal Operator](https://github.com/metal3-io/baremetal-operator)
- [Ironic](https://docs.openstack.org/ironic/latest/)

### Kubernetes & Networking
- [OVN-Kubernetes](https://github.com/ovn-org/ovn-kubernetes)
- [MetalLB](https://metallb.universe.tf/)
- [NMState](https://nmstate.io/)

## Troubleshooting

### Common Issues

**Issue**: Installation fails during bootstrap
```bash
# Check bootstrap logs
./show_bootstrap_log.sh

# SSH to bootstrap node
ssh core@192.168.111.20  # Adjust IP based on your config
```

**Issue**: Ironic services not starting
```bash
# Check Ironic containers
sudo podman ps -a | grep ironic

# View Ironic logs
sudo podman logs <container-id>
```

**Issue**: VM networking issues
```bash
# Verify networks exist
sudo virsh net-list

# Check network configuration
sudo virsh net-dumpxml baremetal
```

**Issue**: Low disk space
```bash
# Check working directory size
df -h ${WORKING_DIR}

# Clean up old images
./cache_cleanup.sh
./podman_cleanup.sh
```
