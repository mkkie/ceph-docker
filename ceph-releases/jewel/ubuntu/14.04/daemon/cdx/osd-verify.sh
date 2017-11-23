#!/bin/bash

function verify_osd {
  if [ -z "${1}" ]; then
    >&2 "ERROR- function verify_osd need to assign a disk."
    exit 1
  else
    local disk="${1}"
  fi

  is_disk_lvm "${disk}" && echo "LVM" && return 0 || true
  is_disk_raid "${disk}" && echo "RAID" && return 0 || true
  ! is_disk_osd "${disk}" && echo "NOT-OSD" && return 0
  ! is_osd_mountable "${disk}" && echo "UNMNT-OSD" && return 0
  ! is_osd_key_correctt "${disk}" && echo "ERR-KEY-OSD" && return 0
  echo "${OSD_ID}"
}

function is_disk_lvm {
  if [ -z "$1" ]; then
    >&2 echo "ERROR- function is_disk_lvm need a disk"
    exit 1
  else
    local disk="${1}"
  fi

  if pvdisplay -C --noheadings --separator ' | ' | grep -q ${disk}; then
    return 0
  else
    return 1
  fi
}

function is_disk_raid {
  if [ -z "$1" ]; then
    >&2 echo "ERROR- function is_disk_raid need a disk"
    exit 1
  else
    local disk=$(echo ${1} | sed 's/\/dev\///')
  fi

  if [ -n "$(cat /proc/mdstat 2>/dev/null | grep md | grep ${disk} | awk '{print $1}')" ]; then
    return 0
  else
    return 1
  fi
}

function is_disk_osd {
  if [ -z "$1" ]; then
    >&2 echo "ERROR- function is_disk_osd need a disk"
    exit 1
  else
    local disk="${1}"
  fi

  if ! sgdisk --verify "${disk}" &>/dev/null; then
    return 2
  elif parted -s "${disk}" print 2>/dev/null | egrep -sq '^ 1.*ceph data'; then
    return 0
  else
    return 3
  fi
}

function is_osd_mountable {
  if [ -z "${1}" ]; then
    >&2 echo "ERROR- function is_osd_mountable need to assign a osd."
    exit 1
  else
    # XXX: only check partition 1
    local diskp1="${1}1"
  fi

  if ceph-disk --setuser ceph --setgroup disk activate "${diskp1}" --no-start-daemon &>/dev/null; then
    return 0
  else
    umount "${diskp1}" &>/dev/null || true
    return 2
  fi
}

function is_osd_key_correctt {
  if [ -z "${1}" ]; then
    >&2 echo "ERROR- function is_osd_key_correctt need to assign a osd."
    exit 1
  else
    # XXX: only check partition 1
    local diskp1="${1}1"
  fi

  # OSD should be mounted by function is_osd_mountable
  local OSD_PATH=$(df | grep "${diskp1}" | awk '{print $6}')
  local TMP_OSD_ID=$(echo "${OSD_PATH}" | sed "s/.*${CLUSTER}-//g")
  local OSD_KEY_IN_CEPH=$(ceph "${CLI_OPTS[@]}" auth get-key osd."${TMP_OSD_ID}" 2>/dev/null)
  if [ -z "${OSD_KEY_IN_CEPH}" ]; then
    umount "${diskp1}" &>/dev/null || true
    return 3
  elif cat "${OSD_PATH}"/keyring | grep -q "${OSD_KEY_IN_CEPH}"; then
    umount "${diskp1}" &>/dev/null || true
    OSD_ID="${TMP_OSD_ID}"
    return 0
  else
    umount "${diskp1}" &>/dev/null || true
    return 4
  fi
}
