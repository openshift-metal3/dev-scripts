# Config Templates

Pre-built configuration templates for common dev-scripts deployment scenarios.

## Quick Start

```bash
# List available templates
./use-template.sh --list

# Activate a template (copies it to config_$USER.sh)
./use-template.sh <template-name>

# Edit to add your CI_TOKEN (if not already set)
vi config_$USER.sh

# Deploy (IPI)
make

# Deploy (Agent-based)
cd agent && ./01_agent_requirements.sh && ./03_agent_build_installer.sh && \
  ./04_agent_prepare_release.sh && ./05_agent_configure.sh && \
  ./06_agent_create_cluster.sh
```

You can also pass `CI_TOKEN` via environment variable to skip the manual edit:

```bash
CI_TOKEN=sha256~your-token ./use-template.sh ipi-ipv4-compact
make
```

## Available Templates

### IPI (Installer Provisioned Infrastructure)

| Template | Description | Masters | Workers | IP Stack |
|----------|-------------|---------|---------|----------|
| `ipi-ipv4-compact` | Compact IPv4 cluster | 3 | 0 | IPv4 |
| `ipi-ipv4-ha` | HA IPv4 cluster | 3 | 2 | IPv4 |
| `ipi-ipv6-ha` | HA IPv6 cluster | 3 | 2 | IPv6 |
| `ipi-dualstack-v4v6-ha` | HA dual-stack cluster (IPv4-primary) | 3 | 2 | v4v6 |
| `ipi-dualstack-v6v4-ha` | HA dual-stack cluster (IPv6-primary) | 3 | 2 | v6v4 |

### Agent-Based Installer

| Template | Description | Scenario | IP Stack |
|----------|-------------|----------|----------|
| `agent-sno-ipv4` | Single Node OpenShift | SNO_IPV4 | IPv4 |
| `agent-sno-ipv6` | Single Node OpenShift | SNO_IPV6 | IPv6 |
| `agent-compact-ipv4` | Compact cluster (3 masters) | COMPACT_IPV4 | IPv4 |
| `agent-ha-ipv4` | HA cluster (3+2) | HA_IPV4 | IPv4 |
| `agent-ha-ipv6` | HA cluster (3+2) | HA_IPV6 | IPv6 |

## Customizing Templates

After activating a template, you can edit `config_$USER.sh` to customize any
settings. See [config_example.sh](../config_example.sh) for a full reference of
all available options.

Common customizations:

```bash
# Change the OCP version
export OPENSHIFT_RELEASE_STREAM="4.21"

# Use a GA release instead of nightly
export OPENSHIFT_RELEASE_TYPE="ga"

# Increase VM resources
export MASTER_MEMORY=32768
export MASTER_VCPU=16

# Change working directory
export WORKING_DIR="/home/dev-scripts"

# Enable FIPS
export FIPS_MODE=true

# Enable MetalLB
export ENABLE_METALLB_MODE="l2"
```

## Creating New Templates

To add a new template, create a `.sh` file in this directory following the
existing naming convention:

- `<method>-<variant>-<ip-stack>.sh`
- Examples: `ipi-ipv4-compact.sh`, `agent-sno-ipv4.sh`

Each template should include:
1. A header comment describing the deployment scenario
2. The `CI_TOKEN` placeholder block
3. Only the settings that differ from defaults
