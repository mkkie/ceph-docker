#!/bin/bash
set -e

source /cdx/osd-verify.sh
source /cdx/config-key.sh

function osd_env_init {
  init_kv "${OSD_KV_PATH}/max_osd" "${MAX_OSD}"
  init_kv "${OSD_KV_PATH}/reserved_slot" "${RESERVED_SLOT}"
  init_kv "${OSD_KV_PATH}/force_format" "${FORCE_FORMAT}"
}

function docker {
  if DOCKER_CMD=$(which docker) 2>/dev/null; then
    bash -c "LD_LIBRARY_PATH=/lib:/host/lib ${DOCKER_CMD} $*"
  fi
}

function get_disks {
  local BLOCKS=$(readlink /sys/class/block/* -e | grep -v "usb" | grep -o "[sv]d[a-z]$")
  [[ -n "${BLOCKS}" ]] || ( echo "" ; return 1 )
  local USB_D=$(readlink /sys/class/block/* -e | grep "usb" | grep -o "[sv]d[a-z]$" || true)
  local RSVD_D
  local SYS_D
  local AVAL_D
  local RESERVED_SLOT=$(get_kv "${OSD_KV_PATH}/reserved_slot")
  if [[ "${RESERVED_SLOT}" == *","* ]]; then
    RESERVED_SLOT=${RESERVED_SLOT//,/ }
  fi
  for slot in ${RESERVED_SLOT}; do
    local RESERVED_D="${RESERVED_D} $(docker exec toolbox port-mapping.sh -s ${slot} 2>/dev/null || true)"
  done
  for disk in ${BLOCKS}; do
    if echo "${RESERVED_D}" | grep -q "${disk}"; then
      RSVD_D="${RSVD_D} ${disk}"
    elif [ -z "$(lsblk /dev/"${disk}" -no MOUNTPOINT | grep -v "/var/lib/ceph/osd/ceph")" ]; then
      AVAL_D="${AVAL_D} ${disk}"
    else
      SYS_D="${SYS_D} ${disk}"
    fi
  done
  # Remove space in the begining
  RSVD_D=$(echo ${RSVD_D} | sed 's/" /"/')
  AVAL_D=$(echo ${AVAL_D} | sed 's/" /"/')
  SYS_D=$(echo ${SYS_D} | sed 's/" /"/')
  # two kind of outputs
  if [ "${1}" == "list" ]; then
    for disk in ${SYS_D}; do echo "${disk} system"; done
    for disk in ${USB_D}; do echo "${disk} usb"; done
    for disk in ${RSVD_D}; do echo "${disk} reserved"; done
    for disk in ${AVAL_D}; do echo "${disk} osd"; done
  else
    local J_FORM="{\"systemDisk\":\"${SYS_D}\",\"usbDisk\":\"${USB_D}\",\"rsvdDisk\":\"${RSVD_D}\",\"avalDisk\":\"${AVAL_D}\"}"
    echo ${J_FORM}
  fi
}

function find_avail_osd {
  # Use shared mem to store parallel variables
  local OSD_READY_LIST=/dev/shm/OSD_READY_LIST && printf "" > "${OSD_READY_LIST}"
  local OSD_AVAIL_LIST=/dev/shm/OSD_AVAIL_LIST && printf "" > "${OSD_AVAIL_LIST}"
  local NOT_AVAIL_LIST=/dev/shm/NOT_AVAIL_LIST && printf "" > "${NOT_AVAIL_LIST}"
  # Determine to format LVM & RAID
  local FORCE_FORMAT=$(get_kv "${OSD_KV_PATH}/force_format")
  echo "${FORCE_FORMAT}" | grep -q "LVM" && local A="LVM" || local A="FALSE"
  echo "${FORCE_FORMAT}" | grep -q "RAID" && local B="RAID" || local B="FALSE"
  # Verify every available disks
  for disk in $(get_disks | jq --raw-output .avalDisk); do
    case $(verify_disk "${disk}") in
      OSD-TRA|OSD-LVM)
        printf "${disk} " >> "${OSD_READY_LIST}" ;;
      ${A}|${B}|DISK)
        printf "${disk} " >> "${OSD_AVAIL_LIST}" ;;
      *)
        printf "${disk} " >> "${NOT_AVAIL_LIST}" ;;
    esac &
  done
  wait
  OSD_READY_LIST=$(cat ${OSD_READY_LIST})
  OSD_AVAIL_LIST=$(cat ${OSD_AVAIL_LIST})
  NOT_AVAIL_LIST=$(cat ${NOT_AVAIL_LIST})
  echo "{\"osdReady\":\"${OSD_READY_LIST}\",\"osdAvail\":\"${OSD_AVAIL_LIST}\",\"notAvail\":\"${NOT_AVAIL_LIST}\"}"
}

function select_osd_disks {
  local OSD_DEV_LIST
  local AVAIL_OSD_JSON=$(find_avail_osd)
  local OSD_READY_NUM=$(echo ${AVAIL_OSD_JSON} | jq --raw-output .osdReady | wc -w)
  local OSD_AVAIL_LIST=$(echo ${AVAIL_OSD_JSON} | jq --raw-output .osdAvail)
  local OSD_AVAIL_NUM=$(echo ${AVAIL_OSD_JSON} | jq --raw-output .osdAvail | wc -w)
  local MAX_OSD=$(get_kv "${OSD_KV_PATH}/max_osd")
  local NEW_OSD_NUM=$(expr "${MAX_OSD}" - "${OSD_READY_NUM}")
  local counter=0

  local OSD_DEV_LIST=$(echo ${AVAIL_OSD_JSON} | jq --raw-output .osdReady)
  for disk in ${OSD_AVAIL_LIST}; do
    if [ "${counter}" -lt "${NEW_OSD_NUM}" ]; then
      OSD_DEV_LIST="${OSD_DEV_LIST} ${disk}"
      let counter=counter+1
    fi
  done
  echo "${OSD_DEV_LIST}"
}

function update_osd_supv_conf {
  # Select OSD and create supervisor configs
  mkdir -p /ceph-osd
  rm -f /ceph-osd/*
  for disk in $(select_osd_disks); do
    cat <<ENDHERE > /ceph-osd/"${disk}"
[program:${disk}]
command=/entrypoint.sh cdx_osd_dev
autostart=true
autorestart=true
startsecs=10
startretries=3
environment=OSD_DEVICE="/dev/${disk}"
ENDHERE
  done
}

## MAIN
function cdx_osd {
  # Check OSD Global KV
  osd_env_init
  # Preparation, only run once
  mkdir -p /var/log/supervisor/
  lvmetad &>/dev/null || true
  echo "files = /ceph-osd/*" >> /etc/supervisor/supervisord.conf
  # Real jobs
  update_osd_supv_conf
  exec supervisord -n
}
