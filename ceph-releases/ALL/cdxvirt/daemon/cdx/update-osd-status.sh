#!/bin/bash

source /cdx/osd.sh

function get_basic_form {
  echo "{\"nodeName\":\"$(hostname)\",\"nodeIp\":\"$(get_ip)\",\"devices\":[]}"
}

function get_ip {
  local nic_more_traffic=$(grep -vE "lo:|face|Inter" /proc/net/dev | sort -n -k 2 | tail -1 | awk '{ sub (":", "", $1); print $1 }')
  local ip=$(ip -4 route show dev "${nic_more_traffic}" | grep proto | awk '{ print $1 }' | grep -v default | grep -vi ^fe80 || true)
  echo "${ip}"
}

function get_osd_status {
  local dev="${1}"
  local app="${2}"
  case ${app} in
    osd)
      local status=$(echo "${SVS_STATUS}" | grep -w "${dev}" | awk '{print $2}')
      echo "${status}"
      ;;
    *) ;;
  esac
}

function get_osd_id {
  local data_part="${1}1"
  local OSD_ID=$(grep "${data_part}" /proc/mounts | awk '{print $2}' | sed -r 's/^.*-([0-9]+)$/\1/' || true)
  echo "${OSD_ID}"
}

function update_disk_info {
  local count=0
  while [ "${count}" -lt "${#DISK[@]}" ];do
    local dev=${DISK[${count}]}
    local app=${DISK[$(expr ${count} + 1)]}
    local count_ind=$(expr ${count} / 2 )
    local J_FORM="{\"name\":\"${dev}\",\"application\":\"${app}\",\"osdStatus\":\"$(get_osd_status ${dev} ${app})\",\"osdId\":\"$(get_osd_id ${dev})\"}"
    JSON=$(echo ${JSON} | jq ".devices[${count_ind}] |= .+ ${J_FORM}")
    let count=count+2
  done
}

# MAIN
DISK=($(get_disks list | sort))
SVS_STATUS=$(supervisorctl status)
JSON=$(get_basic_form)
update_disk_info
mkdir -p /ceph-osd-status/
echo ${JSON} | jq . > /ceph-osd-status/index.html
