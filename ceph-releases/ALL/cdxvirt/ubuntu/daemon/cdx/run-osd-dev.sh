#!/bin/bash
set -e

source cdx/osd-verify.sh

function trad_osd_activate {
  source osd_disk_activate.sh
  osd_activate
}

function lvm_osd_activate {
  source osd_volume_activate.sh
  osd_volume_activate
}

function prepare_activate {
  prepare_trad_osd
  trad_osd_activate
}

function prepare_trad_osd {
  source osd_disk_prepare.sh
  osd_disk_prepare
}

function remove_lvm {
  if ! local pv_display=$(pvdisplay -C --noheadings --separator ' | ' | grep "${OSD_DEVICE}"); then
    return 0
  fi
  local pv_list=$(echo "${pv_display}" | awk -F "|" '{print $1}')
  local vg_list=$(echo "${pv_display}" | awk -F "|" '{print $2}')
  for vg in ${vg_list}; do
    local lv_list=$(lvdisplay -C --noheadings --separator ' | ' | grep -w "${vg}" | awk -F "|" '{print $1}')
    # if lvm mounted, donothing.
    for lv in ${lv_list}; do
      df | grep -q /dev/${vg}/${lv} && return 1
    done
    vgremove -f "${vg}" &>/dev/null
  done
  for pv in ${pv_list}; do
    pvremove -f "${pv}" &>/dev/null
  done
}

function remove_raid {
  local disk=$(echo ${OSD_DEVICE} | sed 's/\/dev\///')
  local md_list=$(cat /proc/mdstat | grep md | grep ${disk} | awk '{print $1}')
  for md in ${md_list}; do
    local dev=$(cat /proc/mdstat | grep -w ${md} | awk '{print $5}' | sed 's/\[.*]//')
    mdadm --stop /dev/"${md}" &>/dev/null
    mdadm --zero-superblock /dev/${dev} &>/dev/null
  done
}

## MAIN
function run_osd_dev {
  # need sdx
  if [ -z "$1" ]; then
    return 1
  elif [[ "${1}" == *"/dev/"* ]]; then
    OSD_DEVICE="${1}"
  else
    OSD_DEVICE="/dev/${1}"
  fi
  # check $OSD_DEVICE
  if ! lsblk "${OSD_DEVICE}" &>/dev/null; then
    exit 1
  else
    local disk=${OSD_DEVICE/\/dev\/}
  fi
  case $(verify_disk "${disk}") in
    OSD-TRA)
      trad_osd_activate
      ;;
    OSD-LVM)
      lvm_osd_activate
      ;;
    LVM|OSD-FLVM)
      remove_lvm
      prepare_activate
      ;;
    RAID)
      remove_raid
      prepare_activate
      ;;
    DISK|OSD-FTRA|*)
      prepare_activate
      ;;
  esac
}
