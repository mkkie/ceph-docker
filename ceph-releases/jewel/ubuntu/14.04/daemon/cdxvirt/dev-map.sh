#!/bin/bash

function get_slot_mapping {
  if [ -z $1 ]; then
    return 0
  fi
  printf '%s\n' "$avail_devs" | while IFS= read -r line
  do
    echo $"$line"
  done | grep -w ^$1 | awk '{print $2}'
}

function get_dev_osdid {
  if [ -z $1 ]; then
    return 0
  fi
  local osd_cont_id=$(docker ps -q -f LABEL=CEPH=osd -f LABEL=DEV_NAME="/dev/$1")
  if [ ! -z ${osd_cont_id} ]; then
    local osd_id=$(docker inspect --format='{{.Config.Labels.OSD_ID}}' "${osd_cont_id}" 2>/dev/null)
  else
    echo ""
    return 0
  fi
  re="^[0-9]+([.][0-9]+)?$"
  if [[ ${osd_id} =~ $re ]]; then
    echo ${osd_id}
  fi
}

function get_dev_model {
  local DEV_NAME="$1"
  if [[ -z ${DEV_NAME} ]]; then
    return 0
  elif [[ $(readlink -f /sys/class/block/${DEV_NAME}| grep '/ata[0-9]*/') ]]; then
    # if no $(...) well cause "conditional binary operator expected "
    local ATA_PORT="$(readlink -f "/sys/class/block/${DEV_NAME}" | sed -n "s/.*ata\([0-9]\{1,3\}\)\/host.*/\1/p")"
    local ID_FILE="/sys/class/ata_device/dev${ATA_PORT}.0/id"
    local count="0"
    echo -n "0x"
    for i in $(cat ${ID_FILE}); do
      ((count++))
      if [[ ${count} -gt "27" && ${count} -le "47" ]];then
        echo -n $(echo $i |cut -c1-2)
        echo -n $(echo $i |cut -c3-4)
      fi
    done
  elif [[ -f "/sys/class/block/${DEV_NAME}/device/model" ]]; then
    local dev_model=$(od -An -t x1 /sys/block/${DEV_NAME}/device/model 2>/dev/null)
    declare -a a_model
    local count="0"
    for i in ${dev_model}; do
       a_model[$count]=$(echo $i)
       ((count++))
    done
    local len="16"
    local count="0"
    echo -n "0x"
    for i in $(seq ${len}); do
      echo -n "${a_model[$count]}"
      ((count++))
    done
  fi
  return 0
}

function get_dev_serial {
  local DEV_NAME="$1"
  if [[ -z ${DEV_NAME} ]]; then
    return 0
  elif [[ $(readlink -f /sys/class/block/${DEV_NAME}| grep '/ata[0-9]*/') ]]; then
    local ATA_PORT="$(readlink -f "/sys/class/block/${DEV_NAME}" | sed -n "s/.*ata\([0-9]\{1,3\}\)\/host.*/\1/p")"
    local ID_FILE="/sys/class/ata_device/dev${ATA_PORT}.0/id"
    local count="0"
    echo -n "0x"
    for i in $(cat ${ID_FILE}); do
      ((count++))
      if [[ ${count} -gt "10" && ${count} -le "20" ]];then
        echo -n $(echo $i |cut -c1-2)
        echo -n $(echo $i |cut -c3-4)
      fi
    done
  elif [[ -f "/sys/class/block/${DEV_NAME}/device/vpd_pg80" ]]; then
    local pg80=$(od -An -t x1 /sys/block/${DEV_NAME}/device/vpd_pg80)
    declare -a a_pg80
    local count="0"
    for i in ${pg80}; do
      a_pg80[$count]=$(echo $i)
      ((count++))
    done
    if [[ ${a_pg80[1]} -eq "80" ]]; then
      local len=$(printf "%d" "0x${a_pg80[3]}")
      local count="4"
      echo -n "0x"
      for i in $(seq ${len}); do
        echo -n "${a_pg80[$count]}"
        ((count++))
      done
    else
      echo "page format error"
      return 0
    fi
  fi
  return 0
}

function get_dev_fwrev {
  local DEV_NAME="$1"
  if [[ -z ${DEV_NAME} ]]; then
    return 0
  elif [[ $(readlink -f /sys/class/block/${DEV_NAME}| grep '/ata[0-9]*/') ]]; then
    local ATA_PORT="$(readlink -f "/sys/class/block/${DEV_NAME}" | sed -n "s/.*ata\([0-9]\{1,3\}\)\/host.*/\1/p")"
    local ID_FILE="/sys/class/ata_device/dev${ATA_PORT}.0/id"
    local count="0"
    echo -n "0x"
    for i in $(cat ${ID_FILE}); do
      ((count++))
      if [[ ${count} -gt "23" && ${count} -le "27" ]];then
        echo -n $(echo $i |cut -c1-2)
        echo -n $(echo $i |cut -c3-4)
      fi
    done
  elif [[ -f "/sys/class/block/${DEV_NAME}/device/rev" ]]; then
    local dev_fwrev=$(od -An -t x1 /sys/block/${DEV_NAME}/device/rev 2>/dev/null)
    declare -a a_rev
    local count="0"
    for i in ${dev_fwrev}; do
      a_rev[$count]=$(echo $i)
      ((count++))
    done
    local len="4"
    local count="0"
    echo -n "0x"
    for i in $(seq ${len}); do
      echo -n "${a_rev[$count]}"
      ((count++))
    done
  fi
  return 0
}

function get_dev_type {
  local DEV_NAME="$1"
  if [ -z ${DEV_NAME} ]; then
    return 0
  elif [[ -f "/sys/block/${DEV_NAME}/queue/rotational" ]]; then
    local dev_type=$(cat /sys/block/${DEV_NAME}/queue/rotational)
    if [[ ${dev_type} -eq "0" ]]; then
      echo -n "SSD"
    elif [[ ${dev_type} -eq "1" ]]; then
      echo -n "HDD"
    fi
  fi
}

function get_osd_map {
  MAPPING_COMMAND="/opt/bin/mapping.sh"
  command -v ${MAPPING_COMMAND} &>/dev/null || { echo "Command not found: \"${MAPPING_COMMAND}\"";exit 1; }
  slot_list=$(${MAPPING_COMMAND} --list-all-slots)
  avail_devs=$(${MAPPING_COMMAND} --list-all-disk-mappings)

  # create json output
  # begin
  osd_map_json='{"node":['

  local counter=1
  local entries=$(echo $slot_list | wc -w)
  for slot in ${slot_list}; do
    dev_name=$(get_slot_mapping ${slot})
    osd_id=$(get_dev_osdid ${dev_name})
    disk_type=$(get_dev_type ${dev_name})
    disk_model=$(get_dev_model ${dev_name})
    disk_serial=$(get_dev_serial ${dev_name})
    disk_fwrev=$(get_dev_fwrev ${dev_name})
    osd_map_json=${osd_map_json}'{"slot":"'$slot'","dev_name":"'${dev_name}'","osd_id":"'${osd_id}'","disk_type":"'${disk_type}'","disk_model":"'${disk_model}'","disk_serial":"'${disk_serial}'","disk_fwrev":"'${disk_fwrev}'"}'

    # add comma
    if [ ${counter} -lt ${entries} ]; then
      osd_map_json=${osd_map_json}','
    fi
    let counter=counter+1
  done
  osd_map_json=${osd_map_json}']}'
  echo ${osd_map_json}
}
