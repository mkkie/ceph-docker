#!/bin/bash

###############
# CEPH STATUS #
###############

function get_ceph_status {
  if ! HEALTH_LOG=$(ceph status -f json 2>/dev/null); then
    log_err "Failed to get Ceph status."
    exit 1
  fi

  MON_LIST=$(echo ${HEALTH_LOG} | jq -r .monmap.mons[].name)
  OVERALL_STATUS=$(echo ${HEALTH_LOG} | jq -r .health.overall_status)

  if [ "${OVERALL_STATUS}" != "HEALTH_OK" ]; then
    HEALTH_DETAIL=$(echo $HEALTH_LOG  | jq -r .health.summary[].summary)
  fi

  if grep -q -w "mons down" <<< ${HEALTH_DETAIL}; then
    MON_UP_LIST=$(echo $HEALTH_LOG  | jq -r .health.timechecks.mons[].name)
    MON_DOWN_LIST=""
    for mon in ${MON_LIST}; do
      grep -q -w ${mon} <<< ${MON_UP_LIST} || MON_DOWN_LIST="${MON_DOWN_LIST} ${mon}"
    done
  fi
}

function ceph_status {
  get_ceph_status
  case ${OVERALL_STATUS} in
    HEALTH_OK)
      echo "HEALTH_OK"
      ;;
    HEALTH_WARN)
      echo "HEALTH_WARN ${HEALTH_DETAIL}"
      ;;
    HEALTH_ERR)
      echo "HEALTH_ERR ${HEALTH_DETAIL}"
      ;;
    *)
      ;;
  esac
}


################
# MON RECOVERY #
################

function fix_monitor {
  get_ceph_status
  if [ -z "${MON_DOWN_LIST}" ]; then
    log "No monitor is down."
    return 0
  fi

  source cdxvirt/mon.sh
  for mon in ${MON_DOWN_LIST}; do
    remove_monitor ${mon}
  done
}

function set_max_mon {
  if [ $# -eq "2" ] && [ $2 == "init" ]; then
    local max_mon_num=$1
    etcdctl -C ${KV_IP}:${KV_PORT} mk ${CLUSTER_PATH}/max_mons ${max_mon_num} &>/dev/null || true
    return 0
  elif [ -z "$1" ]; then
    log_err "Usage: set_max_mon 1~5+"
    exit 1
  else
    local max_mon_num=$1
  fi
  if etcdctl -C ${KV_IP}:${KV_PORT} set ${CLUSTER_PATH}/max_mons ${max_mon_num}; then
    log_success "Expect MON number is \"$1\"."
  else
    log_err "Fail to set \$MAX_MONS"
    return 1
  fi
}

function get_max_mon {
  local MAX_MONS=""
  if MAX_MONS=$(etcdctl -C ${KV_IP}:${KV_PORT} get ${CLUSTER_PATH}/max_mons); then
    echo "${MAX_MONS}"
  else
    log_err "Fail to get \$MAX_MONS"
    return 1
  fi
}
