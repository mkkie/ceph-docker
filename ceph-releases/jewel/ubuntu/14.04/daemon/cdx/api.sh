#!/bin/bash

############
# API MAIN #
############

function cdx_ceph_api {
  case $1 in
    start_all_osds|stop_all_osds|restart_all_osds|get_osd_info|start_or_create_a_osd|stop_a_osd)
      # Commands need docker
      source cdx/osd.sh
      check_osd_env
      $@
      ;;
    set_max_mon|get_max_mon|set_max_osd|get_max_osd|fix_monitor|ceph_verify)
      # Commands in this script part 1
      $@
      ;;
    osd_overview|set_all_replica|start_osd|stop_osd)
      # Commands in this script part 2
      $@
      ;;
    *)
      log "WARN- Wrong options. See function cdx_ceph_api."
      return 2
      ;;
  esac
}

function get_ceph_status {
  get_ceph_admin force &>/dev/null
  if ! HEALTH_LOG=$(ceph "${CLI_OPTS[@]}" status -f json 2>/dev/null); then
    log "ERROR- Failed to get Ceph status."
    exit 1
  fi

  MON_LIST=$(echo "${HEALTH_LOG}" | jq -r .monmap.mons[].name)
  OVERALL_STATUS=$(echo "${HEALTH_LOG}" | jq -r .health.overall_status)

  if [ "${OVERALL_STATUS}" != "HEALTH_OK" ]; then
    HEALTH_DETAIL=$(echo "${HEALTH_LOG}"  | jq -r .health.summary[].summary)
  fi

  if grep -q -w "mons down" <<< "${HEALTH_DETAIL}"; then
    MON_UP_LIST=$(echo "${HEALTH_LOG}"  | jq -r .health.timechecks.mons[].name)
    MON_DOWN_LIST=""
    for mon in ${MON_LIST}; do
      grep -q -w "${mon}" <<< "${MON_UP_LIST}" || MON_DOWN_LIST="${MON_DOWN_LIST} ${mon}"
    done
  fi
}

function remove_monitor {
  if [ -z "$1" ]; then
    log "ERROR- Usage: remove_monitor MON_name"
    exit 1
  else
    local MON_2_REMOVE=$1
  fi

  get_ceph_admin force &>/dev/null

  if ceph "${CLI_OPTS[@]}" mon remove "${MON_2_REMOVE}" 2>>/tmp/ceph_mon_remove_err; then
    log "${MON_2_REMOVE} has been removed."
    get_ceph_admin force &>/dev/null
  else
    log "ERROR- Failes to remove ${MON_2_REMOVE}"
    cat /tmp/ceph_mon_remove_err
    exit 1
  fi

  if [ "${KV_TYPE}" == "etcd" ]; then
    etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" rm "${CLUSTER_PATH}"/mon_host/"${MON_2_REMOVE}" &>/dev/null || true
    source cdx/mon.sh
    update_etcd_monmap &>/dev/null &
  fi
}

function fix_monitor {
  get_ceph_status
  if [ -z "${MON_DOWN_LIST}" ]; then
    log "No monitor is down."
    return 0
  fi

  for mon in ${MON_DOWN_LIST}; do
    remove_monitor "${mon}"
  done
}

function set_max_mon {
  if ! natural_num $1; then
    log "ERROR- Usage: set_max_mon 1~5"
  else
    local max_mon_num="$1"
  fi

  if etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" set "${CLUSTER_PATH}"/max_mon "${max_mon_num}"; then
    log "Expect MON number is $1."
  else
    log "ERROR- Fail to set MAX_MON."
    return 1
  fi
}

function get_max_mon {
  local MAX_MON=""
  if MAX_MON=$(etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" get "${CLUSTER_PATH}"/max_mon); then
    echo "${MAX_MON}"
  else
    log "ERROR- Fail to get MAX_MON."
    return 1
  fi
}

function set_max_osd {
  if ! natural_num $1; then
    log "ERROR- Usage: set_max_mon natural_number."
  else
    local max_osd_num="$1"
  fi

  if etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" set "${CLUSTER_PATH}"/max_osd "${max_osd_num}"; then
    log "Set MAX_OSD to ${max_osd_num}."
  else
    log "ERROR- Fail to set MAX_OSD."
    return 1
  fi
}

function get_max_osd {
  local MAX_OSD=""
  if MAX_OSD=$(etcdctl "${ETCDCTL_OPTS[@]}" "${KV_TLS[@]}" get "${CLUSTER_PATH}"/max_osd); then
    echo "${MAX_OSD}"
  else
    log "ERROR- Fail to get max_osd"
    return 1
  fi
}

function ceph_verify {
  local C_POD=$(kubectl "${K8S_CERT[@]}" "${K8S_NAMESPACE[@]}" get pod \
    2>/dev/null | awk '/ceph-controller-/ {print $1}' | head -1)
  # If conteoller POD is running, then use it to verify.
  local OPTS=$@
  if [ -n "${C_POD}" ]; then
    kubectl "${K8S_CERT[@]}" "${K8S_NAMESPACE[@]}" exec "${C_POD}"  -- bash -c "${OPTS} /entrypoint.sh cdx_verify"
  else
    log "ERROR- Kubenetes controller not exists."
  fi
}

function osd_overview {
  if ! timeout 10 ceph "${CLI_OPTS[@]}" health &>/dev/null; then
    echo "Ceph Cluster isn't ready. Please try again later."
    return 1
  fi
  local O_POD=$(kubectl "${K8S_CERT[@]}" "${K8S_NAMESPACE[@]}" get pod 2>/dev/null | awk '/ceph-osd-/ {print $1}')
  local J_FORM="{\"data\":{\"balanceStatus\":\"\",\"estimateBalanceTime\":\"\",\"nodes\":[]}}"

  # get balance info
  source cdx/balance.sh
  local BAL_INFO=$(cacl_balance)
  local ADD_LIST=$(echo ${BAL_INFO} | jq --raw-output ".addable")
  local MOV_LIST=$(echo ${BAL_INFO} | jq --raw-output ".movable")
  local BAL_STAT=$(echo ${BAL_INFO} | jq --raw-output ".balance")

  local counter=0
  for osd_pod in ${O_POD}; do
    local MOVE_STAT=""
    local NODE_NAME=$(kubectl "${K8S_CERT[@]}" "${K8S_NAMESPACE[@]}" exec "${osd_pod}" hostname 2>/dev/null)
    NODE_NAME="{\"nodeName\":\"${NODE_NAME}\"}"
    if echo "${MOV_LIST}" | grep -q "${NODE_NAME}"; then
      local MOVE_STAT="{\"moveDisk\":\"true\"}"
    else
      local MOVE_STAT="{\"moveDisk\":\"false\"}"
    fi
    J_FORM=$(echo ${J_FORM} | jq ".data.nodes[$counter] |= .+ ${NODE_NAME} + ${MOVE_STAT}")
    let counter=counter+1
  done

  if [ "${BAL_STAT}" == "true" ]; then
    J_FORM=$(echo ${J_FORM} | jq ".data.balanceStatus |= .+ \"balance\"")
  else
    J_FORM=$(echo ${J_FORM} | jq ".data.balanceStatus |= .+ \"inbalance\"")
  fi

  echo ${J_FORM}
}

function set_all_replica {
  echo "set_all_replica"
}

function stop_osd {
  local NODE=${1}
  local DISK=${2}
  if [ -z "${NODE}" ]; then
    echo "ERROR"
    return 1
  elif [ -z "${DISK}" ]; then
    echo "ERROR"
    return 2
  fi
  local O_POD=$(kubectl "${K8S_CERT[@]}" "${K8S_NAMESPACE[@]}" get pod 2>/dev/null | awk '/ceph-osd-/ {print $1}')
  for osd_pod in ${O_POD}; do
    local NODE_NAME=$(kubectl "${K8S_CERT[@]}" "${K8S_NAMESPACE[@]}" exec "${osd_pod}" hostname 2>/dev/null)
    if [ "${NODE_NAME}" == "${NODE}" ]; then
      kubectl "${K8S_CERT[@]}" "${K8S_NAMESPACE[@]}" exec "${osd_pod}" ceph-api stop_a_osd "${DISK}"
      break
    fi
  done
}

function start_osd {
  local NODE=${1}
  local DISK=${2}
  if [ -z "${NODE}" ]; then
    echo "ERROR"
    return 1
  elif [ -z "${DISK}" ]; then
    echo "ERROR"
    return 2
  fi
  local O_POD=$(kubectl "${K8S_CERT[@]}" "${K8S_NAMESPACE[@]}" get pod 2>/dev/null | awk '/ceph-osd-/ {print $1}')
  for osd_pod in ${O_POD}; do
    local NODE_NAME=$(kubectl "${K8S_CERT[@]}" "${K8S_NAMESPACE[@]}" exec "${osd_pod}" hostname 2>/dev/null)
    if [ "${NODE_NAME}" == "${NODE}" ]; then
      kubectl "${K8S_CERT[@]}" "${K8S_NAMESPACE[@]}" exec "${osd_pod}" ceph-api start_or_create_a_osd "${DISK}"
      break
    fi
  done
}

