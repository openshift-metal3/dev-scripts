.PHONY: config_l2 config_bgp start_frr stop_frr run_e2e

all:
	echo "make {config_bgp | config_l2}"

config_l2:
	./metallb_l2.sh

config_bgp: start_frr
	./metallb_bgp.sh

start_frr:
	./start_frr.sh

stop_frr:
	sudo podman kill frr

run_e2e:
	./run_e2e.sh
