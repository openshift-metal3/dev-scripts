#!/usr/bin/env bash
set -euxo pipefail

# This is a test secript that can be used to execute consecutive agent
# agent installs for different configuration scenarios.
# It tests all iterations of the following configuration settings:
# - AGENT_E2E_TEST_SCENARIO
# - MIRROR_IMAGES
# - USE_ZTP_MANIFESTS

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

Type=("COMPACT" "SNO" "HA")
IP=("IPV4" "IPV6" "IPV4V6")
Mode=("DHCP" "STATIC")

Currently_failing_tests=("IPV6" "SNO")

# Set AGENT_E2E_TEST_SCENARIO
Tests=($(for type in ${Type[@]}; do
           for ip in ${IP[@]}; do
             for mode in ${Mode[@]}; do
	       if [[ ${mode} == DHCP ]]; then
	         e2e_test=${type}_${ip}_${mode}
	       else
	         e2e_test=${type}_${ip}
	       fi

	       # Skip tests that are currently failing
	       for failing_test in ${Currently_failing_tests[@]}; do
		   if [[ ${e2e_test} =~ ${failing_test} ]]; then
		     continue 2
		   fi
               done

	       echo "${e2e_test}"
             done
           done
         done))

count=0
USER=`whoami`
config=${SCRIPTDIR}/config_${USER}.sh

for test in ${Tests[@]}; do

  sed -i "s/\(^export AGENT_E2E_TEST_SCENARIO=\)\(.*\)/\1${test}/" ${config}

  for mirror in true false; do
    if [[ $mirror == true ]]; then

      if [[ ${test} =~ "IPV6" ]]; then
	# IPv6 does mirroring by default
        continue
      fi

      echo "mirroring is enabled" >> $SCRIPTDIR/results
      sed -i 's/\(^# export MIRROR_IMAGES=true\)\(.*\)/\export MIRROR_IMAGES=true/' ${config}
    else
      echo "mirroring is disabled" >> $SCRIPTDIR/results
      sed -i 's/\(^export MIRROR_IMAGES=true\)\(.*\)/\# export MIRROR_IMAGES=true/' ${config}
    fi

    for ztp in true false; do
      if [[ $ztp == true ]]; then
        echo "Using ZTP manifests" >> $SCRIPTDIR/results
        sed -i 's/\(^# export AGENT_USE_ZTP_MANIFESTS=true\)\(.*\)/\export AGENT_USE_ZTP_MANIFESTS=true/' ${config} 
      else
        echo "Using install-config and agent-config" >> $SCRIPTDIR/results
        sed -i 's/\(^export AGENT_USE_ZTP_MANIFESTS=true\)\(.*\)/\# export AGENT_USE_ZTP_MANIFESTS=true/' ${config}
      fi

      count=`expr $count + 1`

      echo "Test number $count" > $SCRIPTDIR/results
      echo "make clean" >> $SCRIPTDIR/results 
      make clean &>> $SCRIPTDIR/results
      if [ $? -ne 0 ]; then
	 echo "Make clean Test $count Failed" >> $SCRIPTDIR/results
	 exit
      fi 

      echo "make agent" >> $SCRIPTDIR/results 
      make agent &>> $SCRIPTDIR/results
      if [ $? -ne 0 ]; then
	 echo "Test $count Failed" >> $SCRIPTDIR/results
	 echo "Using $test, mirror=$mirror, ZTP manifests=$ztp"
	 exit
      else
	 echo "Test $count Passed" >> $SCRIPTDIR/results
	 echo "Using $test, mirror=$mirror, ZTP manifests=$ztp"
      fi 

    done
  done
done
