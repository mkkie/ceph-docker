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
