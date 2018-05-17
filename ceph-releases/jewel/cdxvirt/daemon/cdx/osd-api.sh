#!/bin/bash

function stop_all_osds {
  "${DOCKER_CMD}" stop $("${DOCKER_CMD}" ps -q -f LABEL=CEPH=osd)
}

function stop_a_osd {
  local DISK="/dev/${1}"
  if is_osd_running "${DISK}"; then
    "${DOCKER_CMD}" stop $("${DOCKER_CMD}" ps -q -f LABEL=CEPH=osd -f LABEL=DEV_NAME="${DISK}") &>/dev/null
    echo "SUCCESS"
  else
    echo "OSD ALREADY DOWN"
  fi
}

function start_or_create_a_osd {
  local DISK="/dev/${1}"
  local ACT=${2}

  if is_osd_running "${DISK}"; then
    echo "SUCCESS"
    return 0
  fi

  if ! get_avail_disks | grep -q "${DISK}"; then
    >&2 echo "DISK NOT AVAILABLE"
    return 1
  fi

  local OSD_STATUS=$(verify_osd "${DISK}")

  if [ "${ACT}" == "zap" ] && natural_num "${OSD_STATUS}"; then
    >&2 echo "OSD SHOULD NOT BE ZAP"
    return 2
  elif [ "${ACT}" == "zap" ]; then
    ! prepare_new_osd "${DISK}" &>/dev/null && >&2 echo "FAIL TO PREPARE OSD" && return 3 || OSD_STATUS="OSD"
  fi

  case ${OSD_STATUS} in
    LVM)
      echo "DISK IS LVM"
      ;;
    RAID)
      echo "DISK IS RAID"
      ;;
    NOT-OSD)
      ! prepare_new_osd "${DISK}" &>/dev/null && >&2 echo "FAIL TO PREPARE OSD" && return 4
      ! activate_osd "${DISK}" &>/dev/null && >&2 echo "FAIL TO ACTIVATE OSD" && return 5 || echo "SUCCESS"
      ;;
    UNMNT-OSD)
      echo "OSD HAS WRONG INFO"
      ;;
    ERR-KEY-OSD)
      echo "OSD HAS WRONG KEY"
      ;;
    [[:digit:]]*|OSD)
      ! activate_osd "${DISK}" &>/dev/null && >&2 echo "FAIL TO ACTIVATE OSD" && return 6 || echo "SUCCESS"
      ;;
    *)
      echo "ERROR- variable OSD_STATUS not defined in function start_or_create_a_osd."
      exit 3
      ;;
  esac
}

function restart_all_osds {
  "${DOCKER_CMD}" restart $("${DOCKER_CMD}" ps -q -f LABEL=CEPH=osd)
}

function get_osd_info {
  local OSD_CONT_LIST=$("${DOCKER_CMD}" ps -q -f LABEL=CEPH=osd)
  local J_FORM="{\"nodeName\":\"$(hostname)\",\"active\":\"\",\"inactive\":\"\"}"
  local counter=0

  # osd dev list
  local ACT_DEV=""
  for cont in ${OSD_CONT_LIST}; do
    ACT_DEV="${ACT_DEV},$("${DOCKER_CMD}" inspect -f '{{.Config.Labels.DEV_NAME}}' "${cont}" | sed 's/\/dev\///')"
  done
  ACT_DEV=$(echo ${ACT_DEV} | sed 's/,//')

  # disk info
  local ALL_DEV=""
  for disk in $(get_disks | jq --raw-output .avalDisk); do
    if ! echo "${ACT_DEV}" | grep -q "${disk}"; then
      ALL_DEV="${ALL_DEV},${disk}"
    fi
  done
  ALL_DEV=$(echo ${ALL_DEV} | sed 's/,//')

  J_FORM=$(echo ${J_FORM} | jq ".active |= .+ \"${ACT_DEV}\"")
  J_FORM=$(echo ${J_FORM} | jq ".inactive |= .+ \"${ALL_DEV}\"")
  echo "${J_FORM}"
}
