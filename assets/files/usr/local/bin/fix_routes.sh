#!/usr/bin/env bash

dns=$(grep nameserver /etc/resolv.conf | head -1 | awk '{print $2}')
for name in api ns1 test.apps ; do
  vip=$(dig +short $name.$(hostname -d) @$dns)
  viproute=$(ip r | grep $vip)
  vipthere=$(hostname -I | grep $vip)
  if [ ! -z "$viproute" ] &&  [ -z "$vipthere" ] ; then
    echo "$(date) Fixing $name wrong route" >> /var/log/routes.log
    ip route del $vip
  fi
done
