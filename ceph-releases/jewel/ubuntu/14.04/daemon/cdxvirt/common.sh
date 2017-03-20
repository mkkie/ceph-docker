#!/bin/bash

######################
# CDXVIRT ENTRYPOINT #
######################
: ${DEBUG_MODE:=false}
if [ ${DEBUG_MODE} == "true" ]; then
    set -x
fi

source cdxvirt/etcd.sh
if [ ${KV_TYPE} == "etcd" ]; then
    check_KV_IP
fi


#############
# LOG STYLE #
#############

declare -r LOG_DEFAULT_COLOR="\033[0m"
declare -r LOG_ERROR_COLOR="\033[1;31m"
declare -r LOG_INFO_COLOR="\033[1m"
declare -r LOG_SUCCESS_COLOR="\033[1;32m"
declare -r LOG_WARN_COLOR="\033[1;35m"

function log {
  local log_text="$1"
  local log_level="$2"
  local log_color="$3"

  # Default level to "info"
  [[ -z ${log_level} ]] && log_level="INFO";
  [[ -z ${log_color} ]] && log_color="${LOG_INFO_COLOR}";

  echo -e "${log_color}$(date +"%Y-%m-%d %H:%M:%S.%6N") ${log_level} ${log_text} ${LOG_DEFAULT_COLOR}";
  return 0;
}

function log_success { log "$1" "SUCCESS" "${LOG_SUCCESS_COLOR}"; }
function log_err { log "$1" "ERROR" "${LOG_ERROR_COLOR}"; }
function log_warn { log "$1" "WARN" "${LOG_WARN_COLOR}"; }


##############
# DOCKER CMD #
##############

function check_docker_cmd {
  if ! DOCKER_CMD=$(command -v docker 2>/dev/null); then
    log_err "docker: command not found."
    exit 1
  elif ! ${DOCKER_CMD} -v | grep -wq "version"; then
    $DOCKER_CMD -v
    exit 1
  fi
}

function docker {
  local ARGS=""
  for ARG in "$@"; do
    if [[ -n "$(echo "${ARG}" | grep '{.*}' | jq . 2>/dev/null)" ]]; then
      ARGS="${ARGS} \"$(echo ${ARG} | jq -c . | sed "s/\"/\\\\\"/g")\""
    elif [[ "$(echo "${ARG}" | wc -l)" -gt "1" ]]; then
      ARGS="${ARGS} \"$(echo "${ARG}" | sed "s/\"/\\\\\"/g")\""
    else
      ARGS="${ARGS} ${ARG}"
    fi
  done
  [[ "${DEBUG}" == "true" ]] && set -x

  bash -c "LD_LIBRARY_PATH=/lib:/host/lib $(which docker) ${ARGS}"
}


###################
# GET CEPH CONFIG #
###################

function get_ceph_admin {
  # if ceph.conf not exist then get it.
  if [ ! -e /etc/ceph/${CLUSTER}.conf ]; then
    get_config
    check_config
    get_admin_key
    check_admin_key
  fi
  create_socket_dir
}

function get_ceph_conf {
  if [ ! -e /etc/ceph/${CLUSTER}.conf ]; then
    get_config
    check_config
  fi
  create_socket_dir
}

################
# CHECK NUMBER #
################

function positive_num {
  local re="^[1-9][0-9]*$"
  if [[ "$1" =~ $re ]]; then
    return 0
  else
    return 1
  fi
}

function natural_num {
  local re="^[0-9]+([.][0-9]+)?$"
  if [[ "$1" =~ $re ]]; then
    return 0
  else
    return 1
  fi
}


###############
# RESOLV.CONF #
###############
# FIXME: Read dns ip from env
echo -e "search ceph.svc.cluster.local svc.cluster.local cluster.local\nnameserver 10.0.0.10\noptions ndots:5" > /etc/resolv.conf

