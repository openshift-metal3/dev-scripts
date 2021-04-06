#!/bin/bash

# This script manages the day-2 changes that can be made to the 
# provisioning CR, namely, changing between the 'Managed', 'Unmanaged'
# or 'Disabled' modes.

set -xe

source logging.sh

PROV_NETWORK=${1:-"Managed"}

if [ "$PROV_NETWORK" != "Managed" ] && \
   [ "$PROV_NETWORK" != "Unmanaged" ] && \
   [ "$PROV_NETWORK" != "Disabled" ]; then
	echo "Error: Invalid argument."
	echo "Usage: $0 [Managed|Unmanaged|Disabled]"
	exit 1
fi

if [ "$PROV_NETWORK" == "Managed" ]; then
	# Set defaults
	PROV_DHCP_RANGE=${PROV_DHCP_RANGE:-"172.22.0.10,172.22.0.254"}
	PROV_IP=${PROV_IP:-"172.22.0.3"}
	PROV_INT=${PROV_INT:-"enp1s0"}
	PROV_NET_CIDR=${PROV_NET_CIDR:-"172.22.0.0/24"}
fi

if [ "$PROV_NETWORK" == "Unmanaged" ]; then
	PROV_DHCP_RANGE=${PROV_DHCP_RANGE:-""}
	PROV_IP=${PROV_IP:-"172.22.0.3"}
	PROV_INT=${PROV_INT:-"enp1s0"}
	PROV_NET_CIDR=${PROV_NET_CIDR:-"172.22.0.0/24"}
fi

if [ "$PROV_NETWORK" == "Disabled" ]; then
	PROV_DHCP_RANGE=${PROV_DHCP_RANGE:-""}
	PROV_IP=${PROV_IP:-""}
	PROV_INT=${PROV_INT:-""}
	PROV_NET_CIDR=${PROV_NET_CIDR:-""}
fi

# Patch the provisioning-configuration CR
oc patch provisioning provisioning-configuration --type merge -p "{\"provisioningNetwork\": \"${PROV_NETWORK}\", \"spec\":{\"provisioningDHCPRange\": \"${PROV_DHCP_RANGE}\", \"provisioningIP\": \"${PROV_IP}\", \"provisioningInterface\": \"${PROV_INT}\", \"provisioningNetworkCIDR\": \"$PROV_NET_CIDR\"}}"
