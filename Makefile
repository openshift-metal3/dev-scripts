.PHONY: default all agent agent_cleanup agent_build_installer agent_configure agent_create_cluster requirements configure ironic ocp_run install_config clean ocp_cleanup ironic_cleanup host_cleanup cache_cleanup registry_cleanup proxy_cleanup workingdir_cleanup podman_cleanup bell
default: requirements configure build_installer ironic install_config ocp_run bell

all: default

# Deploy cluster with assisted deployment flow
assisted: assisted_deployment bell

# Deploy cluster with agent installer flow
agent: agent_requirements requirements configure agent_build_installer agent_prepare_release agent_configure agent_create_cluster

agent_requirements:
	./agent/01_agent_requirements.sh

agent_build_installer:
	./agent/03_agent_build_installer.sh

agent_prepare_release:
	./agent/04_agent_prepare_release.sh

agent_configure:
	./agent/05_agent_configure.sh

agent_create_cluster:
	./agent/06_agent_create_cluster.sh

agent_cleanup:
	./agent/cleanup.sh

agent_gather:
	./agent/gather.sh

agent_tests:
	./agent/agent_tests.sh

redeploy: ocp_cleanup ironic_cleanup build_installer ironic install_config ocp_run bell

bmc_test: requirements configure build_installer ironic install_config bell

requirements:
	./01_install_requirements.sh

configure:
	./02_configure_host.sh

build_installer:
	./03_build_installer.sh

ironic:
	./04_setup_ironic.sh

install_config:
	./05_create_install_config.sh

ocp_run:
	./06_create_cluster.sh

gather:
	./must_gather.sh

clean: ocp_cleanup ironic_cleanup proxy_cleanup host_cleanup assisted_deployment_cleanup agent_cleanup oc_mirror_cleanup

assisted_deployment_cleanup:
	./assisted_deployment.sh delete_all

ocp_cleanup:
	./ocp_cleanup.sh

ironic_cleanup:
	./ironic_cleanup.sh

host_cleanup:
	./host_cleanup.sh

realclean: clean cache_cleanup workingdir_cleanup podman_cleanup registry_cleanup

cache_cleanup:
	./cache_cleanup.sh

registry_cleanup:
	./registry_cleanup.sh

workingdir_cleanup:
	./workingdir_cleanup.sh

podman_cleanup:
	./podman_cleanup.sh

proxy_cleanup:
	./proxy_cleanup.sh

oc_mirror_cleanup:
	./oc_mirror_cleanup.sh

bell:
	@echo "Done!" $$'\a'

assisted_deployment:
	./assisted_deployment.sh install_assisted_service

assisted_deployment_requirements:
	./assisted_deployment.sh install_prerequisites_assisted_service
