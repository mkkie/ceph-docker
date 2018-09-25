#!/bin/bash

# NOTE: ARGS=("function name" "argv1" "argv2" ....)

function start_osd_api {
  case ${ARGS[1]} in
    all)
      /cdx/ceph-api reload_osd
      supervisorctl update
      supervisorctl start all
      echo "DONE"
      ;;
    *) start_osd_api_check_argv ;;
  esac
}

function start_osd_api_check_argv {
  if [[ "${ARGS[1]}" =~ ^([0-9]|[1-9][0-9]+)$ ]]; then
    /cdx/ceph-api reload_osd
    local device=$(cat /ceph-osd-status | jq --raw-output ".devices[] | select(.osdId==\"${ARGS[1]}\") | .name")
  elif [[ "${ARGS[1]}" =~ ^[sv]d[a-z]$ ]]; then
    /cdx/ceph-api reload_osd
    local device="${ARGS[1]}"
  else
    start_osd_api_usage
  fi
  if ls /ceph-osd | grep -q -w "${device}"; then
    supervisorctl update "${device}"
    supervisorctl start "${device}"
  else
    echo "Device not found or not support."
  fi
}

function start_osd_api_usage {
  echo -e "start_osd all\tStart all osds in this node."
  echo -e "start_osd sdc\tStart a osd with device name like sdc."
  echo -e "start_osd 2\tStart osd.2 if exists."
  exit 1
}

function stop_osd_api {
  case ${ARGS[1]} in
    all)
      supervisorctl stop all
      echo "DONE"
      ;;
    *) stop_osd_api_check_argv ;;
  esac
}

function stop_osd_api_check_argv {
  if [[ "${ARGS[1]}" =~ ^([0-9]|[1-9][0-9]+)$ ]]; then
    /cdx/ceph-api reload_osd
    local device=$(cat /ceph-osd-status | jq --raw-output ".devices[] | select(.osdId==\"${ARGS[1]}\") | .name")
  elif [[ "${ARGS[1]}" =~ ^[sv]d[a-z]$ ]]; then
    /cdx/ceph-api reload_osd
    local device="${ARGS[1]}"
  else
    stop_osd_api_usage
  fi
  if ls /ceph-osd | grep -q -w "${device}"; then
    supervisorctl stop "${device}"
  else
    echo "Device not found or not support."
  fi
}

function stop_osd_api_usage {
  echo -e "stop_osd all\tStop all osds in this node."
  echo -e "stop_osd sdc\tStop a osd with device name like sdc."
  echo -e "stop_osd 2\tStop osd.2 if exists."
  exit 1
}

function reload_osd {
  source /cdx/osd.sh
  update_osd_supv_conf
}

function mon_status {
  local HEALTH_LOG=$(ceph "${CLI_OPTS[@]}" status -f json 2>/dev/null)
  local MON_JSON=$(echo "${HEALTH_LOG}" | jq -r ".monmap.mons[] |= .+ {\"status\":\"\"} | .monmap.mons")
  local MON_DOWN_MSG=$(echo "${HEALTH_LOG}" | jq -r .health.checks.MON_DOWN.summary.message)
  # if message == null, monitors are health
  if [ "${MON_DOWN_MSG}" != "null" ]; then
    for mon in $(echo ${MON_JSON} | jq -r ".[].name"); do
      if echo ${MON_DOWN_MSG} | grep -q -w ${mon}; then
        MON_JSON=$(echo ${MON_JSON} | jq "map(if .name == \"${mon}\" then .status=\"health\" else . end)")
      else
        MON_JSON=$(echo ${MON_JSON} | jq "map(if .name == \"${mon}\" then .status=\"down\" else . end)")
       fi
    done
    echo "${MON_JSON}" | jq "."
  else
    echo "${MON_JSON}" | jq ".[].status |= \"health\""
  fi
}
