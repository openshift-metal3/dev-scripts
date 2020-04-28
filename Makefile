.PHONY: default all requirements configure ironic ocp_run install_config clean ocp_cleanup ironic_cleanup host_cleanup cache_cleanup registry_cleanup workingdir_cleanup podman_cleanup bell
default: requirements configure build_installer ironic install_config ocp_run bell

all: default

redeploy: ocp_cleanup ironic_cleanup build_installer ironic install_config ocp_run bell

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

clean: ocp_cleanup ironic_cleanup host_cleanup

ocp_cleanup:
	./ocp_cleanup.sh

ironic_cleanup:
	./ironic_cleanup.sh

host_cleanup:
	./host_cleanup.sh

realclean: clean cache_cleanup registry_cleanup workingdir_cleanup podman_cleanup

cache_cleanup:
	./cache_cleanup.sh

registry_cleanup:
	./registry_cleanup.sh

workingdir_cleanup:
	./workingdir_cleanup.sh

podman_cleanup:
	./podman_cleanup.sh

bell:
	@echo "Done!" $$'\a'
