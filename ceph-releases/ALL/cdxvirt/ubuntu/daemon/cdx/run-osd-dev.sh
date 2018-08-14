#!/bin/bash
set -e

source cdx/osd-verify.sh

function trad_osd_activate {
  source start_osd.sh
  OSD_TYPE="disk"
  start_osd
}

function lvm_osd_activate {
  ami_privileged
  source osd_volume_activate.sh
  osd_volume_activate
}

function check_user_decision {
  echo "The Device was an OSD."
  echo "You should format or keep data on your decision."
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
  # check $OSD_DEVICE as /dev/sdx
  if [ -z "$1" ] && [ ! -b "${OSD_DEVICE}" ]; then
    log "Bad Block Device \$OSD_DEVICE: ${OSD_DEVICE}"
    return 1
  else
    local disk=${OSD_DEVICE/\/dev\/}
  fi
  case $(verify_disk "${disk}") in
    OSD-TRA|DISK)
      trad_osd_activate
      ;;
    OSD-LVM)
      lvm_osd_activate
      ;;
    LVM)
      remove_lvm
      trad_osd_activate
      ;;
    RAID)
      remove_raid
      trad_osd_activate
      ;;
    OSD-FLVM|OSD-FTRA|*)
      check_user_decision
      ;;
  esac
}
