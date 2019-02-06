.PHONY: default requirements configure repo_sync build ocp_run clean ocp_cleanup libvirt_cleanup
default: requirements configure repo_sync build ocp_run

requirements:
	./01_install_requirements.sh

configure:
	./02_configure_host.sh

repo_sync:
	./03_ocp_repo_sync.sh

build:
	./04_build_ocp_installer.sh

ocp_run:
	./05_run_ocp.sh
	./06_ironic.sh

clean: ocp_cleanup libvirt_cleanup

ocp_cleanup:
	./ocp_cleanup.sh

libvirt_cleanup:
	./libvirt_cleanup.sh
