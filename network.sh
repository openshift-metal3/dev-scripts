#!/bin/bash

source release_info.sh

function nth_ip() {
  network=$1
  idx=$2

  python -c "from ansible_collections.ansible.utils.plugins.filter import nthhost; print(nthhost.nthhost('"$network"', $idx))"
}

function ipversion(){
    if [[ $1 =~ : ]] ; then
        echo 6
        exit
    fi
    echo 4
}

function wrap_if_ipv6(){
    if [ $(ipversion $1) == 6 ] ; then
        echo "[$1]"
        exit
    fi
    echo "$1"
}

export VIPS_SEPARATOR=","
export PATH_CONF_DNSMASQ="/etc/NetworkManager/dnsmasq.d/openshift-${CLUSTER_NAME}.conf"

export IP_STACK=${IP_STACK:-"v6"}
export HOST_IP_STACK=${HOST_IP_STACK:-${IP_STACK}}

# Record the pre-defaulting NETWORK_TYPE
export ORIG_NETWORK_TYPE=${NETWORK_TYPE:-""}

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


if [[ "$HOST_IP_STACK" = "v4" ]]
then
  export PROVISIONING_NETWORK=${PROVISIONING_NETWORK:-"172.22.0.0/24"}
  export EXTERNAL_SUBNET_V4=${EXTERNAL_SUBNET_V4:-"192.168.111.0/24"}
  export EXTERNAL_SUBNET_V6=""
elif [[ "$HOST_IP_STACK" = "v6" ]]; then
  export PROVISIONING_NETWORK=${PROVISIONING_NETWORK:-"fd00:1101::0/64"}
  export EXTERNAL_SUBNET_V4=""
  export EXTERNAL_SUBNET_V6=${EXTERNAL_SUBNET_V6:-"fd2e:6f44:5dd8:c956::/120"}
elif [[ "$HOST_IP_STACK" = "v4v6" ]]; then
  export PROVISIONING_NETWORK=${PROVISIONING_NETWORK:-"172.22.0.0/24"}
  export EXTERNAL_SUBNET_V4=${EXTERNAL_SUBNET_V4:-"192.168.111.0/24"}
  export EXTERNAL_SUBNET_V6=${EXTERNAL_SUBNET_V6:-"fd2e:6f44:5dd8:c956::/120"}
elif [[ "$HOST_IP_STACK" = "v6v4" ]]; then
  export PROVISIONING_NETWORK=${PROVISIONING_NETWORK:-"fd00:1101::0/64"}
  export EXTERNAL_SUBNET_V4=${EXTERNAL_SUBNET_V4:-"192.168.111.0/24"}
  export EXTERNAL_SUBNET_V6=${EXTERNAL_SUBNET_V6:-"fd2e:6f44:5dd8:c956::/120"}
else
  echo "Unexpected setting for HOST_IP_STACK: '${HOST_IP_STACK}'"
  exit 1
fi

function openshift_sdn_deprecated() {
  # OpenShiftSDN is deprecated in 4.15 and later
  printf '4.15\n%s\n' "$(openshift_version)" | sort -V -C
}

if [[ "$IP_STACK" = "v4" ]]
then
  export CLUSTER_SUBNET_V4=${CLUSTER_SUBNET_V4:-"10.128.0.0/14"}
  export CLUSTER_SUBNET_V6=""
  export CLUSTER_HOST_PREFIX_V4=${CLUSTER_HOST_PREFIX_V4:-"23"}
  export CLUSTER_HOST_PREFIX_V6=""
  export SERVICE_SUBNET_V4=${SERVICE_SUBNET_V4:-"172.30.0.0/16"}
  export SERVICE_SUBNET_V6=""
if openshift_sdn_deprecated; then
  export NETWORK_TYPE=${NETWORK_TYPE:-"OVNKubernetes"}
else
  export NETWORK_TYPE=${NETWORK_TYPE:-"OpenShiftSDN"}
fi
elif [[ "$IP_STACK" = "v6" ]]; then
  export CLUSTER_SUBNET_V4=""
  export CLUSTER_SUBNET_V6=${CLUSTER_SUBNET_V6:-"fd01::/48"}
  export CLUSTER_HOST_PREFIX_V4=""
  export CLUSTER_HOST_PREFIX_V6=${CLUSTER_HOST_PREFIX_V6:-"64"}
  export SERVICE_SUBNET_V4=""
  export SERVICE_SUBNET_V6=${SERVICE_SUBNET_V6:-"fd02::/112"}
  export NETWORK_TYPE=${NETWORK_TYPE:-"OVNKubernetes"}
  export MIRROR_IMAGES=${MIRROR_IMAGES:-true}
elif [[ "$IP_STACK" = "v4v6" || "$IP_STACK" = "v6v4" ]]; then
  export CLUSTER_SUBNET_V4=${CLUSTER_SUBNET_V4:-"10.128.0.0/14"}
  export CLUSTER_SUBNET_V6=${CLUSTER_SUBNET_V6:-"fd01::/48"}
  export CLUSTER_HOST_PREFIX_V4=${CLUSTER_HOST_PREFIX_V4:-"23"}
  export CLUSTER_HOST_PREFIX_V6=${CLUSTER_HOST_PREFIX_V6:-"64"}
  export SERVICE_SUBNET_V4=${SERVICE_SUBNET_V4:-"172.30.0.0/16"}
  export SERVICE_SUBNET_V6=${SERVICE_SUBNET_V6:-"fd02::/112"}
  export NETWORK_TYPE=${NETWORK_TYPE:-"OVNKubernetes"}
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

if [[ "${HOST_IP_STACK}" = "v6" || "${HOST_IP_STACK}" = "v6v4" ]]; then
  export PROVISIONING_HOST_EXTERNAL_IP=${PROVISIONING_HOST_EXTERNAL_IP:-$(nth_ip $EXTERNAL_SUBNET_V6 1)}
else
  export PROVISIONING_HOST_EXTERNAL_IP=${PROVISIONING_HOST_EXTERNAL_IP:-$(nth_ip $EXTERNAL_SUBNET_V4 1)}
fi
export MIRROR_IP=${MIRROR_IP:-$PROVISIONING_HOST_EXTERNAL_IP}

if [[ "$PROVISIONING_NETWORK_PROFILE" == "Disabled" ]]; then
  if [[ "${HOST_IP_STACK}" = "v6" ]]; then
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

# Proxy related configuration
if  [[ ! -z "${INSTALLER_PROXY:-}" ]]; then
  export EXT_SUBNET=${EXTERNAL_SUBNET_V6}
  if [[ "$IP_STACK" = "v4" ]]; then
    EXT_SUBNET=${EXTERNAL_SUBNET_V4}
  fi

  HTTP_PROXY=http://$(wrap_if_ipv6 ${PROVISIONING_HOST_EXTERNAL_IP}):${INSTALLER_PROXY_PORT}
  HTTPS_PROXY=http://$(wrap_if_ipv6 ${PROVISIONING_HOST_EXTERNAL_IP}):${INSTALLER_PROXY_PORT}
  NO_PROXY=${PROVISIONING_NETWORK},9999,${EXT_SUBNET}

  if [[ "$PROVISIONING_NETWORK_PROFILE" == "Disabled" ]]; then
    NO_PROXY=${EXT_SUBNET},9999
  fi

  # When a local registry is enabled (usually in disconnected environments), let's add it to the no proxy list
  if [[ ! -z "${MIRROR_IMAGES}" && "${MIRROR_IMAGES,,}" != "false" ]] || [[ ! -z "${ENABLE_LOCAL_REGISTRY}" ]]; then
    NO_PROXY=$NO_PROXY,$LOCAL_REGISTRY_DNS_NAME
  fi
fi

if [ -n "${NETWORK_CONFIG_FOLDER:-}" ]; then
  # We need an absolute path to this location
  NETWORK_CONFIG_FOLDER="$(readlink -m $NETWORK_CONFIG_FOLDER)"
fi

if [[ ! -z "${BOND_CONFIG:-}" && "${BOND_CONFIG}" != 'none' ]]; then
  BOND_PRIMARY_INTERFACE="eth0"
fi

function concat_parameters_with_vipsseparator() {
    # Description:
    #     Adds ${VIPS_SEPARATOR} between all given parameters.
    #
    # Returns:
    #     Print all given parameters with ${VIPS_SEPARATOR} in between.
    
    ARG_NR=1
    RESULT=""
    for ARG in "$@"; do
      RESULT+="${ARG}"
      if [[ $ARG_NR -lt $# ]]; then
        RESULT+="${VIPS_SEPARATOR}"
      fi

      ARG_NR=$((ARG_NR+1))
    done

    echo "${RESULT}"
}

function get_vips() {
    # Arguments:
    #     None
    #
    # Description:
    #     Gets the INGRESS VIP and API VIP addresses (ipv4 and ipv6)
    #
    # Returns:
    #     None
    #
    if [[ -n "${EXTERNAL_SUBNET_V4}" ]]; then
        API_VIPS_V4=$(dig +noall +answer "api.${CLUSTER_DOMAIN}" @$(network_ip ${BAREMETAL_NETWORK_NAME}) | awk '{print $NF}')
        INGRESS_VIPS_V4=$(nth_ip $EXTERNAL_SUBNET_V4 4)
    fi

    if [[ -n "${EXTERNAL_SUBNET_V6}" ]]; then
        API_VIPS_V6=$(dig -t AAAA +noall +answer "api.${CLUSTER_DOMAIN}" @$(network_ip ${BAREMETAL_NETWORK_NAME}) | awk '{print $NF}')
        INGRESS_VIPS_V6=$(nth_ip $EXTERNAL_SUBNET_V6 4)
    fi

    if [[ "$IP_STACK" == "v4" || "$IP_STACK" == "v4v6" ]]; then
        API_VIPS=$(concat_parameters_with_vipsseparator ${API_VIPS_V4:-} ${API_VIPS_V6:-})
        INGRESS_VIPS=$(concat_parameters_with_vipsseparator ${INGRESS_VIPS_V4:-} ${INGRESS_VIPS_V6:-})
    else
        API_VIPS=$(concat_parameters_with_vipsseparator ${API_VIPS_V6:-} ${API_VIPS_V4:-})
        INGRESS_VIPS=$(concat_parameters_with_vipsseparator ${INGRESS_VIPS_V6:-} ${INGRESS_VIPS_V4:-})
    fi
}

function add_dnsmasq_multi_entry() {
    # Arguments:
    #     First argument: the type of entry to be added in openshift-${CLUSTER_NAME}.conf
    #     Types available: apivip OR ingressvip
    #
    #     Second argument: The list (or single entry) of apivip or ingressvip
    #
    # Description:
    #     Add entries into openshift-${CLUSTERNAME}.conf for dnsmasq
    #
    # Returns:
    #     None
    for i in ${2//${VIPS_SEPARATOR}/ }; do
        if [ "${1}" = "apivip" ] ; then
            echo "address=/api.${CLUSTER_DOMAIN}/${i}" | sudo tee -a "${PATH_CONF_DNSMASQ}"
        fi

        if [ "${1}" = "ingressvip" ] ; then
            echo "address=/.apps.${CLUSTER_DOMAIN}/${i}" | sudo tee -a "${PATH_CONF_DNSMASQ}"
        fi
    done
}

function configure_dnsmasq() {
  apiVips=${1}
  ingressVips=${2}

  # make sure the dns_masq config file is cleaned up (add_dnsmasq_multi_entry() only appends)
  rm -f "${PATH_CONF_DNSMASQ}"

  add_dnsmasq_multi_entry "apivip" "${apiVips}"
  add_dnsmasq_multi_entry "ingressvip" "${ingressVips}"

  echo "listen-address=::1" | sudo tee -a "${PATH_CONF_DNSMASQ}"

  # Risk reduction for CVE-2020-25684, CVE-2020-25685, and CVE-2020-25686
  # See: https://access.redhat.com/security/vulnerabilities/RHSB-2021-001
  echo "cache-size=0" | sudo tee -a "${PATH_CONF_DNSMASQ}"

  sudo systemctl reload NetworkManager
}

function set_api_and_ingress_vip() {
  # NOTE: This is equivalent to the external API DNS record pointing the API to the API VIP
  if [ "$MANAGE_BR_BRIDGE" == "y" ] ; then
      get_vips
      configure_dnsmasq ${API_VIPS} ${INGRESS_VIPS}
  else
      # Specific for users *NOT* using devscript with KVM (virsh) for deploy. (Reads: baremetal)
      if [[ -z "${EXTERNAL_SUBNET_V4}" ]]; then
          API_VIPS=$(dig -t AAAA +noall +answer "api.${CLUSTER_DOMAIN}"  | awk '{print $NF}')
      else
          API_VIPS=$(dig +noall +answer "api.${CLUSTER_DOMAIN}"  | awk '{print $NF}')
      fi
      INGRESS_VIPS=$(dig +noall +answer "test.apps.${CLUSTER_DOMAIN}" | awk '{print $NF}')
  fi
}
