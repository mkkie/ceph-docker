#!/bin/bash
set -e

: "${FORCE_FORMAT:=LVM RAID}"

function find_avail_osd {
  # Use shared mem to store parallel variables
  local OSD_READY_LIST=/dev/shm/OSD_READY_LIST && printf "" > "${OSD_READY_LIST}"
  local OSD_AVAIL_LIST=/dev/shm/OSD_AVAIL_LIST && printf "" > "${OSD_AVAIL_LIST}"
  local NOT_AVAIL_LIST=/dev/shm/NOT_AVAIL_LIST && printf "" > "${NOT_AVAIL_LIST}"
  # Determine to format LVM & RAID
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

function verify_disk {
  # need sdx
  if [ -z "$1" ]; then
    return 1
  elif [[ "${1}" == *"/dev/"* ]]; then
    local disk=${1/\/dev\//}
  else
    local disk="${1}"
  fi
  # OSD-TRA & OSD-FTRA (traditional osd & failed)
  if is_trad_osd "${disk}"; then
    is_trad_osd_mountable "${disk}" && echo "OSD-TRA" && return
    echo "OSD-FTRA" && return
  fi
  # LVM & OSD-LVM & OSD-FLVM (lvm osd & failed)
  # XXX: check OSD-LVM available or not
  if is_disk_lvm "${disk}"; then
    if is_lvm_osd "${disk}"; then
      is_lvm_osd_mountable "${disk}" && echo "OSD-LVM" && return
      echo "OSD-FLVM" && return
    fi
    echo "LVM" && return
  fi
  # RAID
  if is_disk_raid "${disk}"; then
    echo "RAID" && return
  fi
  # OTHER
  echo "DISK"
}

function is_trad_osd {
  # $1 change to /dev/sdx
  if [ -z "$1" ]; then
    return 1
  else
    # $1 change to /dev/sdx
    local disk="/dev/${1}"
  fi
  if parted --script "${disk}" print 2>/dev/null | grep -qE '^ 1.*ceph data'; then
    return 0
  else
    return 1
  fi
}

function is_trad_osd_mountable {
  # $1 change to /dev/sdx
  if [ -z "$1" ]; then
    return 1
  else
    # XXX: only check partition 1
    local diskp1="/dev/${1}1"
  fi
  if df | grep "/var/lib/ceph/osd/" | grep -q "${diskp1}"; then
    return 0
  elif ceph-disk --setuser ceph --setgroup disk activate "${diskp1}" --no-start-daemon &>/dev/null; then
    return 0
  else
    umount "${diskp1}" &>/dev/null || true
    return 2
  fi
}

function is_disk_lvm {
  if [ -z "$1" ]; then
    return 1
  else
    # $1 change to /dev/sdx
    local disk="/dev/${1}"
  fi
  if pvdisplay -C --noheadings --separator ' | ' | grep -q "${disk}"; then
    return 0
  else
    return 1
  fi
}

function is_lvm_osd {
  if [ -z "$1" ]; then
    return 1
  else
    # $1 change to /dev/sdx
    local disk="/dev/${1}"
  fi
  if ceph-volume lvm list "${disk}" &>/dev/null; then
    return 0
  else
    return 1
  fi
}

function is_lvm_osd_mountable {
  if [ -z "$1" ]; then
    return 1
  else
    # $1 change to /dev/sdx
    local disk="/dev/${1}"
  fi
  local LVM_OSD_JSON=$(ceph-volume lvm list "$OSD_DEVICE" --format json)
  local OSD_ID="$(echo ${LVM_OSD_JSON} | jq --raw-output keys[0])"
  local OSD_FSID=$(echo ${LVM_OSD_JSON} | jq --raw-output ".\"${OSD_ID}\" | .[].tags.\"ceph.osd_fsid\"")
  if ceph-volume lvm activate --no-systemd "${OSD_ID}" "${OSD_FSID}" &>/dev/null; then
    return 0
  else
    return 1
  fi
}

function is_disk_raid {
  if [ -z "$1" ]; then
    return 1
  else
    # $1 change to /dev/sdx
    local disk="/dev/${1}"
  fi
  if [ -n "$(cat /proc/mdstat 2>/dev/null | grep md | grep ${disk} | awk '{print $1}')" ]; then
    return 0
  else
    return 1
  fi
}
