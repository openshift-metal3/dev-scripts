.PHONY: config_l2 config_bgp start_frr stop_frr run_e2e

all:
	echo "make {config_bgp | config_l2}"

config_metallb:
	./configure_metallb.sh

run_e2e:
	./run_e2e.sh
