#!/bin/bash
set -e

source /cdx/config-key.sh
: "${EP_UPDATE_INTERVAL:=60}"

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
  ${KUBECTL} patch ep ceph-mon -p "${J_FORM}"
}

# MAIN
function cdx_controller {
  init_kv "${CTRL_KV_PATH}/ep_update_interval" "${EP_UPDATE_INTERVAL}"
  EP_UPDATE_INTERVAL=$(get_kv "${CTRL_KV_PATH}/ep_update_interval")
  while [ true ]; do
    update_ceph_mon_ep
    sleep "${EP_UPDATE_INTERVAL}"
  done
}
