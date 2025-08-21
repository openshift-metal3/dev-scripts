# Metal3 Requirements Installation - Ansible Version

This directory contains the Ansible playbook version of the original `01_install_requirements.sh` script. The playbook provides the same functionality but with better organization, error handling, and idempotency.

## Files

- `install_requirements.yml` - Main Ansible playbook
- `tasks/` - Directory containing individual task files
- `inventory.ini` - Simple localhost inventory
- `run_install_requirements.sh` - Wrapper script (optional)
- `README_ansible.md` - This documentation

## Requirements

- Ansible installed on the system
- Root/sudo access
- RHEL/CentOS 8 or 9 (or compatible distributions like AlmaLinux, Rocky Linux)

## Usage

### Option 1: Direct Ansible Playbook

```bash
ansible-playbook -i inventory.ini install_requirements.yml -v
```

### Option 2: Using the Wrapper Script

```bash
./run_install_requirements.sh
```

## Environment Variables

The playbook respects the same environment variables as the original script:

- `WORKING_DIR` - Working directory (default: current directory)
- `METAL3_DEV_ENV_PATH` - Path to metal3-dev-env repository
- `METAL3_DEV_ENV` - If set, skips repo cloning
- `ANSIBLE_VERSION` - Ansible version to install (default: 8.0.0)
- `GO_VERSION` - Go version for the metal3 playbook (default: 1.22.3)
- `OPENSHIFT_CLIENT_TOOLS_URL` - URL for OpenShift client tools
- `KNI_INSTALL_FROM_GIT` - Install additional packages for git-based installation
- `PERSISTENT_IMAGEREG` - Install NFS utilities for persistent image registry
- `NODES_PLATFORM` - Install platform-specific tools (e.g., 'baremetal' installs ipmitool)
- `ALMA_PYTHON_OVERRIDE` - Python override for AlmaLinux

## Task Organization

The playbook is organized into the following tasks:

1. **early_deploy_validation.yml** - Basic validation checks
2. **setup_metal3_repo.yml** - Clone and setup metal3-dev-env repository
3. **configure_dnf.yml** - Configure DNF for faster downloads
4. **upgrade_packages.yml** - Upgrade system packages
5. **install_passlib.yml** - Install passlib with platform-python
6. **setup_rhel8_repos.yml** - Configure repositories for RHEL/CentOS 8
7. **setup_rhel9_repos.yml** - Configure repositories for RHEL/CentOS 9
8. **install_yq.yml** - Install yq YAML processor
9. **install_dev_packages.yml** - Install development packages
10. **install_python_packages.yml** - Install Python dependencies
11. **install_ansible.yml** - Install Ansible and galaxy requirements
12. **run_metal3_playbook.yml** - Run the metal3 installation playbook
13. **install_optional_packages.yml** - Install optional packages based on environment
14. **handle_docker_distribution.yml** - Handle docker-distribution service
15. **install_oc_tools.yml** - Install OpenShift client tools

## Features

- **Idempotent**: Can be run multiple times safely
- **Better Error Handling**: Ansible provides better error reporting
- **Modular**: Tasks are organized in separate files for maintainability
- **OS Detection**: Automatically detects RHEL/CentOS version and architecture
- **Conditional Logic**: Only runs tasks relevant to the current environment

## Differences from Original Script

1. **Structured Tasks**: Logic is organized into reusable task files
2. **Fact Gathering**: Uses Ansible facts instead of shell commands where possible
3. **Package Management**: Uses Ansible's dnf module instead of shell commands
4. **Service Management**: Uses Ansible's systemd module for service operations
5. **File Operations**: Uses Ansible modules for file and directory operations

## Troubleshooting

- Ensure you have sudo privileges
- Check that your OS is supported (RHEL/CentOS 8 or 9)
- Verify network connectivity for package downloads
- Check Ansible version compatibility

## Migration from Bash Script

To migrate from the bash script:

1. Ensure all environment variables are set as needed
2. Run the Ansible playbook instead of the bash script
3. The playbook will perform the same operations with better error handling

For any issues, compare the task outputs with the original script behavior.
