#!/bin/bash
set -e

function update_ceph_mon_ep {
  local MON_STATUS=$(/cdx/ceph-api mon_status)
  local HEALTH_MONS=($(echo ${MON_STATUS} | jq -r ".[] | select(.status==\"health\") | .addr" | sed 's/:.*//'))
  local J_FORM="{\"subsets\": [{\"addresses\": [${IP_FORM}],\"ports\": [{\"port\": 6789,\"protocol\": \"TCP\"}]}]}"
  # update ep by HEALTH_MONS
  local count=0
  if [ -z "${HEALTH_MONS}" ]; then
    retuen 1
  else
    count=0
    for ip in ${HEALTH_MONS[@]}; do
      J_FORM=$(echo ${J_FORM} | jq ".subsets[].addresses[${count}] |= .+ {\"ip\":\"${ip}\"}")
      let count=count+1
    done
  fi
  kubectl patch ep ceph-mon -p "${J_FORM}"
}
