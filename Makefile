.PHONY: default requirements configure repo_sync ironic build ocp_run clean ocp_cleanup host_cleanup
default: requirements configure repo_sync ironic build ocp_run

requirements:
	./01_install_requirements.sh

configure:
	./02_configure_host.sh

repo_sync:
	./03_ocp_repo_sync.sh

ironic:
	./04_setup_ironic.sh

build:
	./05_build_ocp_installer.sh

ocp_run:
	./06_deploy_bootstrap_vm.sh
	./07_deploy_masters.sh

clean: ocp_cleanup host_cleanup

ocp_cleanup:
	./ocp_cleanup.sh

host_cleanup:
	./host_cleanup.sh

