.PHONY: default all requirements configure repo_sync ironic ocp_run register_hosts clean ocp_cleanup ironic_cleanup host_cleanup bell csr_hack
default: requirements configure repo_sync ironic ocp_run register_hosts csr_hack bell

all: default

redeploy: ocp_cleanup ironic_cleanup ironic ocp_run register_hosts csr_hack bell

requirements:
	./01_install_requirements.sh

configure:
	./02_configure_host.sh

repo_sync:
	./03_ocp_repo_sync.sh

ironic:
	./04_setup_ironic.sh

ocp_run:
	./06_create_cluster.sh

register_hosts:
	./11_register_hosts.sh

csr_hack:
	./12_csr_hack.sh

clean: ocp_cleanup ironic_cleanup host_cleanup

ocp_cleanup:
	./ocp_cleanup.sh

ironic_cleanup:
	./ironic_cleanup.sh

host_cleanup:
	./host_cleanup.sh

bell:
	@echo "Done!" $$'\a'
