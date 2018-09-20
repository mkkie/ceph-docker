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

