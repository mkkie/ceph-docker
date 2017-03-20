#!/bin/bash

##############
# CRUSH INIT #
##############

function crush_initialization {
  # DO NOT EDIT DEFAULT POOL
  DEFAULT_POOL=rbd

  # Default crush leaf [ osd | host ] & replication size 1 ~ 9
  : ${DEFAULT_CRUSH_LEAF:=osd}
  : ${DEFAULT_POOL_COPIES:=1}

  # check ceph command is usable
  until timeout 10 ceph health &>/dev/null; do
    log_warn "Waitiing for ceph cluster is ready."
  done

  # set lock to avoid multiple node writting together
  until etcdctl -C ${KV_IP}:${KV_PORT} mk ${CLUSTER_PATH}/osd_init_lock ${HOSTNAME} > /dev/null 2>&1; do
    local LOCKER_NAME=$(kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} get ${CLUSTER_PATH}/osd_init_lock)
    if [[ ${LOCKER_NAME} == ${HOSTNAME} ]]; then
      log_warn "Last time Crush Initialization is locked by ${HOSTNAME} itself."
      break
    else
      log_warn "Crush Initialization is locked by ${LOCKER_NAME}. Waiting..."
      sleep 3
    fi
  done

  # check complete status
  if kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} get ${CLUSTER_PATH}/initialization_complete > /dev/null 2>&1 ; then
    log_success "We detected a complete status, no need to initialize."
  else

    # initialization of crushmap
    log "Initialization of crushmap"
    # create a crush rule, chooseleaf as osd.
    ceph ${CEPH_OPTS} osd crush rule create-simple replicated_type_osd default osd firstn

    # crush_ruleset 0 for host, 1 for osd
    case "${DEFAULT_CRUSH_LEAF}" in
      host)
        set_crush_ruleset ${DEFAULT_POOL} 0
        ;;
      osd)
        set_crush_ruleset ${DEFAULT_POOL} 1
        ;;
      *)
        log_warn "DEFAULT_CRUSH_LEAF not in [ osd | host ], do nothing"
        ;;
    esac

    # Replication size of rbd pool
    # check size in the range 1 ~ 9
    local re='^[1-9]$'

    if ! [[ ${DEFAULT_POOL_COPIES} =~ ${re} ]]; then
      local size_defined_on_etcd=$(kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} get ${CLUSTER_PATH}/global/osd_pool_default_size)
      ceph ${CEPH_OPTS} osd pool set ${DEFAULT_POOL} size ${size_defined_on_etcd}
      log_warn "DEFAULT_POOL_COPIES is not in the range 1 ~ 9, using default value ${size_defined_on_etcd}"
    else
      ceph ${CEPH_OPTS} osd pool set ${DEFAULT_POOL} size ${DEFAULT_POOL_COPIES}
    fi

    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} put ${CLUSTER_PATH}/initialization_complete true > /dev/null 2>&1
  fi

  log "Removing lock for ${HOSTNAME}"
  kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} del ${CLUSTER_PATH}/osd_init_lock > /dev/null 2>&1

}


################
# CRUSH ADJUST #
################

function auto_change_crush {
  # DO NOT EDIT DEFAULT POOL
  DEFAULT_POOL=rbd
  : ${CRUSH_TYPE:=space}
  : ${PGs_PER_OSD:=64}

  # If there are no osds, We don't change pg_num
  health_log=$(timeout 10 ceph health 2>/dev/null)
  if echo ${health_log} | grep -q "no osds"; then
    return 0
  fi

  # set lock to avoid multiple node writting together
  until etcdctl -C ${KV_IP}:${KV_PORT} mk ${CLUSTER_PATH}/osd_crush_lock ${HOSTNAME} > /dev/null 2>&1; do
    local LOCKER_NAME=$(kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} get ${CLUSTER_PATH}/osd_crush_lock)
    if [[ ${LOCKER_NAME} == ${HOSTNAME} ]]; then
      log_warn "Last time auto_change_crush is locked by ${HOSTNAME} itself."
      break
    else
      log_warn "Auto_change_crush is locked by ${LOCKER_NAME}. Waiting..."
      sleep 10
    fi
  done

  # NODES not include some host weight=0
  NODEs=$(ceph ${CEPH_OPTS} osd tree | awk '/host/ { print $2 }' | grep -v ^0$ -c || true)
  # Only count OSD that status is up
  OSDs=$(ceph ${CEPH_OPTS} osd stat | awk '{ print $5 }')
  # Put crush type into ETCD
  kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} put ${CLUSTER_PATH}/crush_type ${CRUSH_TYPE} >/dev/null 2>&1

  case "${CRUSH_TYPE}" in
    none)
      log_success "Disable changing crush rule automatically."
      ;;
    space)
      crush_type_space
      ;;
    safety)
      crush_type_safety
      ;;
    *)
      log_warn "Definition of CRUSH_TYPE error. Do nothing."
      log_warn "Disable changing crush rule automatically."
      log_warn "CRUSH_TYPE: [ none | space | safety ]."
      ;;
  esac

  log "Removing lock for ${HOSTNAME}"
  kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} del ${CLUSTER_PATH}/osd_crush_lock > /dev/null 2>&1
}

# auto change pg & crush leaf. Max replications is 2.
function crush_type_space {
  # RCs not greater than 2
  if [ ${NODEs} -eq "0" ]; then
    log_warn "No Storage Node, do nothing with changing crush_type"
    return 0
  elif [ ${NODEs} -eq "1" ]; then
    set_pool_size ${DEFAULT_POOL} 1
  else
    set_pool_size ${DEFAULT_POOL} 2
  fi

  # multiple = OSDs / 2, pg_num = PGs_PER_OSD x multiple
  local prefix_multiple=$(expr ${OSDs} '+' 1)
  local multiple=$(expr ${prefix_multiple} '/' 2)
  if [ ${multiple} -lt "1" ]; then
    local multiple=1
  fi
  local PG_NUM=$(expr ${PGs_PER_OSD} '*' ${multiple})
  set_pg_num ${DEFAULT_POOL} ${PG_NUM}
  auto_change_crush_leaf 2
}

# auto change pg & crush leaf. Max replications is 3.
function crush_type_safety {
  # RCs not greater than 3
  if [ ${NODEs} -eq "0" ]; then
    log_warn "No Storage Node, do nothing with changing crush_type"
    return 0
  elif [ ${NODEs} -lt "3" ]; then
    set_pool_size ${DEFAULT_POOL} ${NODEs}
  else
    set_pool_size ${DEFAULT_POOL} 3
  fi

  # multiple = OSDs / 3, pg_num = PGs_PER_OSD x multiple
  local prefix_multiple=$(expr ${OSDs} '+' 1)
  local multiple=$(expr ${prefix_multiple} '/' 3)
  if [ ${multiple} -lt "1" ]; then
    local multiple=1
  fi
  local PG_NUM=$(expr ${PGs_PER_OSD} '*' ${multiple})
  set_pg_num ${DEFAULT_POOL} ${PG_NUM}
  auto_change_crush_leaf 2
}

# usage: auto_change_crush_leaf ${MAX_COPIES}
function auto_change_crush_leaf {
  # crush_ruleset 0 for host, 1 for osd
  if [ ${NODEs} -ge $1 ]; then
    set_crush_ruleset ${DEFAULT_POOL} 0
  else
    set_crush_ruleset ${DEFAULT_POOL} 1
  fi
}

function set_crush_ruleset {
  # $1 = pool_name $2 = crush_ruleset
  log "Set pool \"$1\" crush_ruleset to \"$2\""
  if ! ceph ${CEPH_OPTS} osd pool set $1 crush_ruleset $2 2>/dev/null; then
    log_warn "Fail to set crush_ruleset of $1 pool"
    return 0
  fi
}

function set_pool_size {
  # $1 = pool_name $2 = pool_size
  log "Set pool \"$1\" replications to \"$2\""
  if ! ceph ${CEPH_OPTS} osd pool set $1 size $2 2>/dev/null; then
    log_warn "Fail to set replications of $1 pool"
    return 0
  fi
}

function set_pg_num {
  # $1 = pool_name, $2 = pg_num
  log "Set pool \"$1\" pg_num to \"$2\""
  if ! ceph ${CEPH_OPTS} osd pool set $1 pg_num $2 2>/dev/null; then
    log_warn "Fail to set pg_num of $1 pool"
    return 0
  fi

  # wait for pg_num resized and change pgp_num
  until [ $(ceph ${CEPH_OPTS} -s | grep creating -c) -eq 0 ]; do
    sleep 5
  done
  if ! ceph ${CEPH_OPTS} osd pool set $1 pgp_num $2 2>/dev/null; then
    log_warn "Fail to Set pgp_num of $1 pool"
    return 0
  fi
}

