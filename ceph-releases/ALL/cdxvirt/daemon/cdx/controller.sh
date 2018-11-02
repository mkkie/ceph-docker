#!/bin/bash
set -e

source /cdx/config-key.sh
: "${EP_UPDATE_INTERVAL:=60}"
: "${MAX_MON:=3}"
: "${MON_LABEL:=cdx/ceph-mon}"
: "${MGR_LABEL:=cdx/ceph-mgr}"

function update_ceph_mon_ep {
  if ! timeout 10 ceph -s; then
    echo "Ceph not in a ready status."
    return 0
  fi
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

function set_k8s_label {
  k8s_nodes=$(kubectl get node --show-labels | sed "1d")
  mon_nodes=($(echo "${k8s_nodes}" | grep -w "${MON_LABEL}" | awk '{print $1}'))
  not_mon_nodes=($(echo "${k8s_nodes}" | grep -w -v "${MON_LABEL}" | awk '{print $1}'))
  mgr_nodes=($(echo "${k8s_nodes}" | grep -w "${MGR_LABEL}" | awk '{print $1}'))
  not_mgr_nodes=($(echo "${k8s_nodes}" | grep -w -v "${MGR_LABEL}" | awk '{print $1}'))

  # how many mons needs to add?
  if [ "${#mon_nodes[@]}" -lt "${MAX_MON}" ]; then
    local mon_num2add=$(expr "${MAX_MON}" - "${#mon_nodes[@]}")
  else
    local mon_num2add=0
  fi
  # create kubernetes mon label
  local counter=0
  for mon2add in ${not_mon_nodes[@]}; do
    if [ "${counter}" -lt "${mon_num2add}" ]; then
      kubectl label node "${mon2add}" "${MON_LABEL}=true" --overwrite &>/dev/null && echo "Add Mon node ${mon2add}"
      let counter=counter+1
    fi
  done
  # create kubernetes mon label
  if [ "${#mgr_nodes[@]}" -eq "0" ] && [ "${#not_mgr_nodes[@]}" -ne "0" ]; then
    kubectl label node "${not_mgr_nodes[0]}" "${MGR_LABEL}=true" --overwrite &>/dev/null && echo "Add Mgr node ${not_mgr_nodes[0]}"
  fi
}

function check_health {
  if timeout 10 ceph -s; then
    return 0
  else
    echo "Ceph not in a ready status."
    return 1
  fi
}

# MAIN
function cdx_controller {
  if check_health; then
    init_kv "${CTRL_KV_PATH}/ep_update_interval" "${EP_UPDATE_INTERVAL}"
    init_kv "${MON_KV_PATH}/max_mon" "${MAX_MON}"
    EP_UPDATE_INTERVAL=$(get_kv "${CTRL_KV_PATH}/ep_update_interval")
    MAX_MON=$(get_kv "${MON_KV_PATH}/max_mon")
  fi
  while [ true ]; do
    set_k8s_label
    if check_health; then
      update_ceph_mon_ep
    fi
    sleep "${EP_UPDATE_INTERVAL}"
  done
}
