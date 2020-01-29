.PHONY: default all requirements configure ironic ocp_run clean ocp_cleanup ironic_cleanup host_cleanup bell
default: requirements configure build_installer ironic ocp_run bell

all: default

redeploy: ocp_cleanup ironic_cleanup build_installer ironic ocp_run bell

requirements:
	./01_install_requirements.sh

configure:
	./02_configure_host.sh

build_installer:
	./03_build_installer.sh

ironic:
	./04_setup_ironic.sh

ocp_run:
	./06_create_cluster.sh

clean: ocp_cleanup ironic_cleanup host_cleanup

ocp_cleanup:
	./ocp_cleanup.sh

ironic_cleanup:
	./ironic_cleanup.sh

host_cleanup:
	./host_cleanup.sh

podman_cleanup:
	./podman_cleanup.sh

bell:
	@echo "Done!" $$'\a'
