#!/bin/bash

function nth_ip() {
  network=$1
  idx=$2

  python -c "from ansible.plugins.filter import ipaddr; print(ipaddr.nthhost('"$network"', $idx))"
}


export IP_STACK=${IP_STACK:-"v6"}

EXTERNAL_SUBNET=${EXTERNAL_SUBNET:-""}
EXTERNAL_SUBNET_V4=${EXTERNAL_SUBNET_V4:-""}
EXTERNAL_SUBNET_V6=${EXTERNAL_SUBNET_V6:-""}
if [[ -n "${EXTERNAL_SUBNET}" ]] && [[ -z "${EXTERNAL_SUBNET_V4}" ]] && [[ -z "${EXTERNAL_SUBNET_V6}" ]]; then
    # Backwards compatibility.  If the old var was specified, and neither of the new
    # vars are set, automatically adapt it to the right new var.
    if [[ "${EXTERNAL_SUBNET}" =~ .*:.* ]]; then
        export EXTERNAL_SUBNET_V6="${EXTERNAL_SUBNET}"
    else
        export EXTERNAL_SUBNET_V4="${EXTERNAL_SUBNET}"
    fi
elif [[ -n "${EXTERNAL_SUBNET}" ]]; then
    echo "EXTERNAL_SUBNET has been removed in favor of EXTERNAL_SUBNET_V4 and EXTERNAL_NETWORK_V6."
    echo "Please update your configuration to drop the use of EXTERNAL_SUBNET."
    exit 1
fi

SERVICE_SUBNET=${SERVICE_SUBNET:-""}
SERVICE_SUBNET_V4=${SERVICE_SUBNET_V4:-""}
SERVICE_SUBNET_V6=${SERVICE_SUBNET_V6:-""}
if [[ -n "${SERVICE_SUBNET}" ]] && [[ -z "${SERVICE_SUBNET_V4}" ]] && [[ -z "${SERVICE_SUBNET_V6}" ]]; then
    # Backwards compatibility.  If the old var was specified, and neither of the new
    # vars are set, automatically adapt it to the right new var.
    if [[ "${SERVICE_SUBNET}" =~ .*:.* ]]; then
        export SERVICE_SUBNET_V6="${SERVICE_SUBNET}"
    else
        export SERVICE_SUBNET_V4="${SERVICE_SUBNET}"
    fi
elif [[ -n "${SERVICE_SUBNET}" ]]; then
    echo "SERVICE_SUBNET has been removed in favor of SERVICE_SUBNET_V4 and SERVICE_SUBNET_V6."
    echo "Please update your configuration to drop the use of SERVICE_SUBNET."
    exit 1
fi

CLUSTER_SUBNET=${CLUSTER_SUBNET:-""}
CLUSTER_SUBNET_V4=${CLUSTER_SUBNET_V4:-""}
CLUSTER_SUBNET_V6=${CLUSTER_SUBNET_V6:-""}
CLUSTER_HOST_PREFIX=${CLUSTER_HOST_PREFIX:-""}
CLUSTER_HOST_PREFIX_V4=${CLUSTER_HOST_PREFIX_V4:-""}
CLUSTER_HOST_PREFIX_V6=${CLUSTER_HOST_PREFIX_V6:-""}
if [[ -n "${CLUSTER_SUBNET}" ]] && [[ -z "${CLUSTER_SUBNET_V4}" ]] && [[ -z "${CLUSTER_SUBNET_V6}" ]]; then
    # Backwards compatibility.  If the old var was specified, and neither of the new
    # vars are set, automatically adapt it to the right new var.
    if [[ "${CLUSTER_SUBNET}" =~ .*:.* ]]; then
        export CLUSTER_SUBNET_V6="${CLUSTER_SUBNET}"
        export CLUSTER_HOST_PREFIX_V6="${CLUSTER_HOST_PREFIX_V6:-${CLUSTER_HOST_PREFIX}}"
    else
        export CLUSTER_SUBNET_V4="${CLUSTER_SUBNET}"
        export CLUSTER_HOST_PREFIX_V4="${CLUSTER_HOST_PREFIX_V4:-${CLUSTER_HOST_PREFIX}}"
    fi
elif [[ -n "${CLUSTER_SUBNET}" ]]; then
    echo "CLUSTER_SUBNET has been removed in favor of CLUSTER_SUBNET_V4 and CLUSTER_SUBNET_V6."
    echo "Please update your configuration to drop the use of CLUSTER_SUBNET."
    exit 1
fi


if [[ "$IP_STACK" = "v4" ]]
then
  export PROVISIONING_NETWORK=${PROVISIONING_NETWORK:-"172.22.0.0/24"}
  export EXTERNAL_SUBNET_V4=${EXTERNAL_SUBNET_V4:-"192.168.111.0/24"}
  export EXTERNAL_SUBNET_V6=""
  export CLUSTER_SUBNET_V4=${CLUSTER_SUBNET_V4:-"10.128.0.0/14"}
  export CLUSTER_SUBNET_V6=""
  export CLUSTER_HOST_PREFIX_V4=${CLUSTER_HOST_PREFIX_V4:-"23"}
  export CLUSTER_HOST_PREFIX_V6=""
  export SERVICE_SUBNET_V4=${SERVICE_SUBNET_V4:-"172.30.0.0/16"}
  export SERVICE_SUBNET_V6=""
  export NETWORK_TYPE=${NETWORK_TYPE:-"OpenShiftSDN"}
elif [[ "$IP_STACK" = "v6" ]]; then
  export PROVISIONING_NETWORK=${PROVISIONING_NETWORK:-"fd00:1101::0/64"}
  export EXTERNAL_SUBNET_V4=""
  export EXTERNAL_SUBNET_V6=${EXTERNAL_SUBNET_V6:-"fd2e:6f44:5dd8:c956::/120"}
  export CLUSTER_SUBNET_V4=""
  export CLUSTER_SUBNET_V6=${CLUSTER_SUBNET_V6:-"fd01::/48"}
  export CLUSTER_HOST_PREFIX_V4=""
  export CLUSTER_HOST_PREFIX_V6=${CLUSTER_HOST_PREFIX_V6:-"64"}
  export SERVICE_SUBNET_V4=""
  export SERVICE_SUBNET_V6=${SERVICE_SUBNET_V6:-"fd02::/112"}
  export NETWORK_TYPE=${NETWORK_TYPE:-"OVNKubernetes"}
  export MIRROR_IMAGES=true
  export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/local-release-image:latest"
elif [[ "$IP_STACK" = "v4v6" ]]; then
  export PROVISIONING_NETWORK=${PROVISIONING_NETWORK:-"fd00:1101::0/64"}
  export EXTERNAL_SUBNET_V4=${EXTERNAL_SUBNET_V4:-"192.168.111.0/24"}
  export EXTERNAL_SUBNET_V6=${EXTERNAL_SUBNET_V6:-"fd2e:6f44:5dd8:c956::/120"}
  export CLUSTER_SUBNET_V4=${CLUSTER_SUBNET_V4:-"10.128.0.0/14"}
  export CLUSTER_SUBNET_V6=${CLUSTER_SUBNET_V6:-"fd01::/48"}
  export CLUSTER_HOST_PREFIX_V4=${CLUSTER_HOST_PREFIX_V4:-"23"}
  export CLUSTER_HOST_PREFIX_V6=${CLUSTER_HOST_PREFIX_V6:-"64"}
  export SERVICE_SUBNET_V4=${SERVICE_SUBNET_V4:-"172.30.0.0/16"}
  export SERVICE_SUBNET_V6=${SERVICE_SUBNET_V6:-"fd02::/112"}
  export NETWORK_TYPE=${NETWORK_TYPE:-"OVNKubernetes"}
  export MIRROR_IMAGES=true
  export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/local-release-image:latest"
else
  echo "Unexpected setting for IP_STACK: '${IP_STACK}'"
  exit 1
fi

if [[ "${IP_STACK}" = "v6" ]]; then
  export DNS_VIP=${DNS_VIP:-$(nth_ip $EXTERNAL_SUBNET_V6 2)}
else
  export DNS_VIP=${DNS_VIP:-$(nth_ip $EXTERNAL_SUBNET_V4 2)}
fi

# Provisioning network information
export CLUSTER_PRO_IF=${CLUSTER_PRO_IF:-enp1s0}
export PROVISIONING_NETMASK=${PROVISIONING_NETMASK:-$(ipcalc --netmask $PROVISIONING_NETWORK | cut -d= -f2)}

export PROVISIONING_HOST_IP=${PROVISIONING_HOST_IP:-$(nth_ip $PROVISIONING_NETWORK 1)}

if [[ "${IP_STACK}" = "v6" ]]; then
  export PROVISIONING_HOST_EXTERNAL_IP=${PROVISIONING_HOST_EXTERNAL_IP:-$(nth_ip $EXTERNAL_SUBNET_V6 1)}
  export PROVISIONING_HOST_EXTERNAL_NETMASK=${PROVISIONING_HOST_EXTERNAL_NETMASK:-$(ipcalc --netmask $EXTERNAL_SUBNET_V6 | cut -d= -f2)}
else
  export PROVISIONING_HOST_EXTERNAL_IP=${PROVISIONING_HOST_EXTERNAL_IP:-$(nth_ip $EXTERNAL_SUBNET_V4 1)}
  export PROVISIONING_HOST_EXTERNAL_NETMASK=${PROVISIONING_HOST_EXTERNAL_NETMASK:-$(ipcalc --netmask $EXTERNAL_SUBNET_V4 | cut -d= -f2)}
fi
export MIRROR_IP=${MIRROR_IP:-$PROVISIONING_HOST_EXTERNAL_IP}

if [[ "$PROVISIONING_NETWORK_PROFILE" == "Disabled" ]]; then
  if [[ "${IP_STACK}" = "v6" ]]; then
    export PROVISIONING_IP_SUBNET=$EXTERNAL_SUBNET_V6
  else
    export PROVISIONING_IP_SUBNET=$EXTERNAL_SUBNET_V4
  fi

  # When the provisioning network is disabled, we use IP's on the external network for the provisioning IP's:
  export BOOTSTRAP_PROVISIONING_IP=${BOOTSTRAP_PROVISIONING_IP:-$(nth_ip $PROVISIONING_IP_SUBNET 7)}
  export CLUSTER_PROVISIONING_IP=${CLUSTER_PROVISIONING_IP:-$(nth_ip $PROVISIONING_IP_SUBNET 8)}
else
  export BOOTSTRAP_PROVISIONING_IP=${BOOTSTRAP_PROVISIONING_IP:-$(nth_ip $PROVISIONING_NETWORK 2)}
  export CLUSTER_PROVISIONING_IP=${CLUSTER_PROVISIONING_IP:-$(nth_ip $PROVISIONING_NETWORK 3)}
fi
