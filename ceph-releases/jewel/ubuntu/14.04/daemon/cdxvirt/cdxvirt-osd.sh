#!/bin/bash

source cdxvirt-crush.sh

###########
# OSD ENV #
###########

function osd_controller_env {
  : ${OSD_INIT_MODE:=minimal}
  : ${MAX_OSDS:=1}
  : ${OSD_FOLDER:="/var/lib/ceph/osd"}

  check_docker_cmd

  mkdir -p ${OSD_FOLDER}
  chown ceph. ${OSD_FOLDER}
  if [ -n "${OSD_MEM}" ]; then OSD_MEM="-m ${OSD_MEM}"; fi
  if [ -n "${OSD_CPU_CORE}" ]; then OSD_CPU_CORE="-c ${OSD_CPU_CORE}"; fi
  set_max_osd ${MAX_OSDS} init
}

##################
# OSD CONTROLLER #
##################

function osd_controller {
  get_ceph_admin
  crush_initialization
  osd_controller_env
  run_osds

  log "Start ETCD watcher."
  /bin/bash -c "/bin/bash /cdxvirt-etcd-watcher.sh init" &

  log "Loop & check hotplug OSDs."
  hotplug_OSD
}

function run_osds {
  start_all_osds
  add_new_osd auto
  auto_change_crush
}

function get_active_osd_nums {
  ${DOCKER_CMD} ps -q -f LABEL=CEPH=osd | wc -l
}

function stop_all_osds {
  ${DOCKER_CMD} stop $(${DOCKER_CMD} ps -q -f LABEL=CEPH=osd)
}

function restart_all_osds {
  ${DOCKER_CMD} restart $(${DOCKER_CMD} ps -q -f LABEL=CEPH=osd)
}

function start_all_osds {
  # get all avail disks
  local DISKS=$(get_avail_disks)

  if [ -z "${DISKS}" ]; then
    log_err "No available disk"
    return 0
  fi

  for disk in ${DISKS}; do
    if [ "$(is_osd_disk ${disk})" == "true" ]; then
      activate_osd $disk
    fi
  done
}

function activate_osd {
  if [ -z "$1" ]; then
    log_err "function activate_osd need to assign a OSD."
    return 1
  else
    local disk2act=$1
  fi

  # if OSD is running or come from another cluster, then return 0.
  if is_osd_running ${disk2act}; then
    local CONT_ID=$(${DOCKER_CMD} ps -q -f LABEL=CEPH=osd -f LABEL=DEV_NAME=${disk2act})
    log_success "${disk2act} is running as OSD (${CONT_ID})."
    return 0
  elif ! is_osd_correct ${disk2act}; then
    log_warn "The OSD disk ${disk2act} unable to activate for current Ceph cluster."
    return 0
  fi

  local CONT_NAME=$(create_cont_name ${disk2act} ${OSD_ID})
  if $DOCKER_CMD inspect ${CONT_NAME} &>/dev/null; then
    $DOCKER_CMD rm ${CONT_NAME} >/dev/null
  fi

  # XXX: auto find DAEMON_VERSION
  $DOCKER_CMD run -d -l CLUSTER=${CLUSTER} -l CEPH=osd -l DEV_NAME=${disk2act} -l OSD_ID=${OSD_ID} \
    --name=${CONT_NAME} --privileged=true --net=host --pid=host -v /dev:/dev ${OSD_MEM} ${OSD_CPU_CORE} \
    -e KV_TYPE=${KV_TYPE} -e KV_PORT=${KV_PORT} -e DEBUG_MODE=${DEBUG_MODE} -e OSD_DEVICE=${disk2act} \
    -e OSD_TYPE=activate ${DAEMON_VERSION} osd >/dev/null

  # XXX: check OSD container status continuously
  sleep 3
  if is_osd_running ${disk2act}; then
    local CONT_ID=$(${DOCKER_CMD} ps -q -f LABEL=CEPH=osd -f LABEL=DEV_NAME=${disk2act})
    log_success "Success to activate ${disk2act} (${CONT_ID})."
  fi
}

function add_new_osd {
  # if $1 is null, then add one osd.
  if [ -z "$1" ]; then
    add_n=1
  elif [ "$1" == "auto" ]; then
    add_n=$(calc_osd2add)
  else
    add_n=$1
  fi

  if ! natural_num ${add_n}; then
    log_err "\${add_n} is not a natural number."
    return 1
  fi

  # find available disks.
  DISKS=""
  for disk in $(get_avail_disks); do
    if ! is_osd_running ${disk}; then
      DISKS="${DISKS} ${disk}"
    fi
  done
  if [ -z "${DISKS}" ]; then
    log_warn "No available disk for adding a new OSD."
    return 0
  fi

  # find disks not having OSD partitions.
  disks_without_osd=""
  for disk in ${DISKS}; do
    if [ "$(is_osd_disk ${disk})" == "false" ]; then
      disks_without_osd="${disks_without_osd} ${disk}"
    fi
  done

  osd_add_list=""
  # Three cases for selecting osd disks and print to $osd_add_list.
  case "${OSD_INIT_MODE}" in
    minimal)
      # Ignore OSD disks. But if No OSDs in cluster, force to choose one.
      if [ -n "${disks_without_osd}" ]; then
        select_n_disks "${disks_without_osd}" ${add_n}
      elif [ -z "${disks_without_osd}" ] && timeout 10 ceph health 2>/dev/null | grep -q "no osds"; then
        # TODO: Deploy storage PODs on two or more storage node concurrently,
        # every node will force to choose one and use it.
        # We hope only one disk in the cluster will be format.
        osd_add_list=$(echo ${DISKS} | awk '{print $1}')
      fi
      ;;
    force)
      # Force to select all disks
      select_n_disks "${DISKS}" ${add_n}
      ;;
    strict)
      # Ignore all OSD disks.
      select_n_disks "${disks_without_osd}" ${add_n}
      ;;
    *)
      ;;
  esac

  if [ -n "${osd_add_list}" ]; then
    # clear lvm & raid
    clear_lvs_disks
    clear_raid_disks
  else
    return 0
  fi

  for disk in ${osd_add_list}; do
    if ! prepare_new_osd ${disk}; then
      log_err "OSD ${disk} fail to prepare."
    elif ! activate_osd ${disk}; then
      log_err "OSD ${disk} fail to activate."
    fi
  done
}

function calc_osd2add {
  if ! max_osd_num=$(etcdctl get ${CLUSTER_PATH}/max_osd_num_per_node); then
    max_osd_num=1
  fi

  if [ $(get_active_osd_nums) -ge "${max_osd_num}" ]; then
    echo "0"
  else
    local osd_num2add=$(expr ${max_osd_num} - $(get_active_osd_nums))
    echo ${osd_num2add}
  fi
}

function select_n_disks {
  local counter=0
  for disk in $1; do
    if [ "${counter}" -lt "$2" ]; then
      osd_add_list="${osd_add_list} ${disk}"
      let counter=counter+1
    fi
  done
}

function prepare_new_osd {
  if [ -z "$1" ]; then
    log_err "prepare_new_osd need to assign a disk."
    return 1
  else
    local osd2prep=$1
  fi
  local CONT_NAME="$(create_cont_name ${osd2prep})_prepare_$(date +%N)"
  sgdisk --zap-all --clear --mbrtogpt ${osd2prep}
  if $DOCKER_CMD run -l CLUSTER=${CLUSTER} -l CEPH=osd_prepare -l DEV_NAME=osd2prep --name=${CONT_NAME} \
    --privileged=true -v /dev/:/dev/ -e KV_PORT=2379 -e KV_TYPE=etcd -e OSD_TYPE=prepare \
    -e OSD_DEVICE=${osd2prep} -e OSD_FORCE_ZAP=1 ${DAEMON_VERSION} osd &>/dev/null; then
    return 0
  else
    return 1
  fi
}

function create_cont_name {
  # usage: create_cont_name DEV_PATH OSD_ID, e.g. create_cont_name /dev/sda 12 => OSD_12_sda
  if [ $# -ne 2 ] && [ $# -ne 1 ]; then
    log_err "create_cont_name DEV_PATH OSD_ID"
    return 1
  fi
  if echo "$1" | grep -q "^/dev/"; then
    local SHORT_DEV_NAME=$(echo "$1" | sed 's/\/dev\///g')
  else
    local SHORT_DEV_NAME=""
  fi

  if [ -z "${SHORT_DEV_NAME}" ] && [ -z "$2" ]; then
    echo "OSD"
  elif [ -z "${SHORT_DEV_NAME}" ]; then
    echo "OSD_$2"
  elif [ -z "$2" ]; then
    echo "OSD_${SHORT_DEV_NAME}"
  else
    echo "OSD_$2_${SHORT_DEV_NAME}"
  fi
}

function set_max_osd {
  if ! natural_num $1; then
    log_err "MAX_OSDS must be a natural number."
  elif [ $# -eq "2" ] && [ $2 == "init" ]; then
    local max_osd_num=$1
    etcdctl mk ${CLUSTER_PATH}/max_osd_num_per_node ${max_osd_num} &>/dev/null || true
    return 0
  else
    local max_osd_num=$1
  fi
  if etcdctl set ${CLUSTER_PATH}/max_osd_num_per_node ${max_osd_num}; then
    log_success "Set MAX_OSDS to ${max_osd_num}."
  else
    log_err "Fail to set MAX_OSDS."
    return 1
  fi
}

function get_max_osd {
  local MAX_OSDS=""
  if MAX_OSDS=$(etcdctl get ${CLUSTER_PATH}/max_osd_num_per_node); then
    echo "${MAX_OSDS}"
  else
    log_err "Fail to get max_osd_num_per_node"
    return 1
  fi
}

function is_osd_running {
  # give a disk and check OSD container
  if [ -z "$1" ]; then
    log_err "function is_osd_running need to assign a OSD."
    exit 1
  else
    local DEV_NAME=$1
  fi

  # check running & exited containers
  local CONT_ID=$(${DOCKER_CMD} ps -q -f LABEL=CEPH=osd -f LABEL=DEV_NAME=${DEV_NAME})
  if [ -n "${CONT_ID}" ]; then
    return 0
  else
    return 1
  fi
}

function is_osd_correct {
  if [ -z "$1" ]; then
    log_err "function is_osd_correct need to assign a OSD."
    exit 1
  else
    # FIXME: disk2verify is a variable ti find ceph data JOURNAL partition.
    disk2verify=$1
  fi

  disk2verify="${disk2verify}1"
  if ceph-disk --setuser ceph --setgroup disk activate ${disk2verify} --no-start-daemon &>/dev/null; then
    OSD_ID=$(df | grep "${disk2verify}" | sed "s/.*${CLUSTER}-//g")
    umount ${disk2verify}
    return 0
  else
    OSD_ID=""
    umount ${disk2verify} &>dev/null || true
    return 1
  fi
}

function is_osd_disk {
  # Check label partition table includes "ceph journal" or not
  if ! sgdisk --verify $1 &>/dev/null; then
    echo "false"
  elif parted -s $1 print 2>/dev/null | egrep -sq '^ 1.*ceph data' ; then
    echo "true"
  else
    echo "false"
  fi
}

# Find disks not only unmounted but also non-ceph disks
function get_avail_disks {
  BLOCKS=$(readlink /sys/class/block/* -e | grep -v "usb" | grep -o "sd[a-z]$")
  [[ -n "${BLOCKS}" ]] || ( echo "" ; return 1 )

  while read disk ; do
    # Double check it
    if ! lsblk /dev/${disk} > /dev/null 2>&1; then
      continue
    fi

    if [ -z "$(lsblk /dev/${disk} -no MOUNTPOINT)" ]; then
      # Find it
      echo "/dev/${disk}"
    fi
  done < <(echo "$BLOCKS")
}

function hotplug_OSD {
  inotifywait -r -m /dev/ -e CREATE -e DELETE | while read dev_msg; do
    local hotplug_disk=$(echo $dev_msg | awk '{print $1$3}')
    local action=$(echo $dev_msg | awk '{print $2}')

    if [[ "${hotplug_disk}" =~ /dev/sd[a-z]$ ]]; then
      case "${action}" in
        CREATE)
          run_osds
          ;;
        DELETE)
          log "Remove ${hotplug_disk}"
          if is_osd_running ${hotplug_disk}; then
            local CONT_ID=$(${DOCKER_CMD} ps -q -f LABEL=CEPH=osd -f LABEL=DEV_NAME=${hotplug_disk})
            ${DOCKER_CMD} stop ${CONT_ID} &>/dev/null || true
          fi
          ;;
        *)
          ;;
      esac
    fi
  done
}

# XXX: We suppose we don't need any lvs and raid disks at all and just delete them
function clear_lvs_disks {
  lvs=$(lvscan | grep '/dev.*' | awk '{print $2}')

  if [ -n "$lvs" ]; then
    log "Find logic volumes, inactive them."
    for lv in $lvs
    do
      lvremove -f "${lv//\'/}"
    done

  fi

  vgs=$(vgdisplay -C --noheadings --separator '|' | cut -d '|' -f 1)
  if [ -n "$vgs" ]; then
    log "Find VGs, delete them."
    for vg in $vgs
    do
      vgremove -f "$vg"
    done

  fi


  pvs=$(pvscan -s | grep '/dev/sd[a-z].*' || true)
  if [ -n "$pvs" ]; then
    log "Find PVs, delete them."
    for pv in $pvs
    do
      pvremove -ff -y "$pv"
    done

  fi
}

function clear_raid_disks {
  mds=$(mdadm --detail --scan  | awk '{print $2}')

  if [ -z "${mds}" ]; then
    # Nothing to do
    return 0
  fi

  for md in ${mds}
  do
    devs=$(mdadm --detail --export "${md}" | grep MD_DEVICE_.*_DEV | cut -d '=' -f 2)
    if [ -z "$devs" ]; then
      log "No invalid devices"
      return 1
    fi
    mdadm --stop ${md}

    for dev in ${devs}
    do
      log "Clear MD device: $dev"
      mdadm --wait --zero-superblock --force "$dev"
    done
  done
}

