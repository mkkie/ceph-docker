#!/bin/bash
set -e

source cdx/osd-verify.sh

: "${RESERVED_SLOT:=}"
: "${MAX_OSD:=8}"

function docker {
  if DOCKER_CMD=$(which docker) 2>/dev/null; then
    bash -c "LD_LIBRARY_PATH=/lib:/host/lib ${DOCKER_CMD} $*"
  fi
}

function get_disks {
  local BLOCKS=$(readlink /sys/class/block/* -e | grep -v "usb" | grep -o "sd[a-z]$")
  [[ -n "${BLOCKS}" ]] || ( echo "" ; return 1 )
  local USB_D=$(readlink /sys/class/block/* -e | grep "usb" | grep -o "[sv]d[a-z]$" || true)
  local RSVD_D
  local SYS_D
  local AVAL_D
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
  local J_FORM="{\"systemDisk\":\"${SYS_D}\",\"usbDisk\":\"${USB_D}\",\"rsvdDisk\":\"${RSVD_D}\",\"avalDisk\":\"${AVAL_D}\"}"
  echo ${J_FORM}
}

function get_avail_disks {
  local AVAL_D=$(get_disks | jq --raw-output .avalDisk)
  for disk in ${AVAL_D}; do
    echo "/dev/${disk}"
  done
}

function start_osd {
  select_osd_disks
  prepare_active_osd
}

function select_osd_disks {
  local OSD_DEV_LIST
  local AVAIL_OSD_JSON=$(find_avail_osd)
  local OSD_READY_NUM=$(echo ${AVAIL_OSD_JSON} | jq --raw-output .osdReady | wc -w)
  local OSD_AVAIL_LIST=$(echo ${AVAIL_OSD_JSON} | jq --raw-output .osdAvail)
  local OSD_AVAIL_NUM=$(echo ${AVAIL_OSD_JSON} | jq --raw-output .osdAvail | wc -w)
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

## MAIN
function cdx_osd {
  # Preparation, only run once
  mkdir -p /ceph-osd /var/log/supervisor/
  lvmetad &>/dev/null || true
  echo "files = /ceph-osd/*" >> /etc/supervisor/supervisord.conf

  # Select OSD and create supervisor configs
  for disk in $(select_osd_disks); do
    cat <<ENDHERE > /ceph-osd/"${disk}"
[program:${disk}]
command=/entrypoint.sh cdx_osd_dev ${disk}
autostart=true
autorestart=true
startsecs=10
startretries=3
ENDHERE
  done

  exec supervisord -n
}
