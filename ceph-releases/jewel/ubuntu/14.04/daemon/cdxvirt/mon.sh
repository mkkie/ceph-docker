#!/bin/bash

###########
# MON ENV #
###########

function mon_controller_env {
  : ${K8S_IP:=https://${KUBERNETES_SERVICE_HOST}}
  : ${K8S_PORT:=${KUBERNETES_SERVICE_PORT}}
  : ${K8S_CERT:="--certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt --token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"}
  : ${NAMESPACE:=ceph}
  : ${POD_SELECTOR:="ceph-mon"}
  : ${EP_NAME:="ceph-mon"}
  : ${MON_LABEL:="cdxvirt/ceph_mon"}
}


#############
# MON CHECK #
#############

function check_mon {
  : ${K8S_IP:=${KV_IP}}
  : ${K8S_PORT:=8080}
  get_mon_network
  verify_mon_folder
  verify_monmap
}

function get_mon_network {
  if [ -n "${CEPH_PUBLIC_NETWORK}" ] && [ ${KV_TYPE} == "etcd" ]; then
    MON_IP=$(ip -4 -o a | awk '{ sub ("/..", "", $4); print $4 }' | grepcidr "${CEPH_PUBLIC_NETWORK}" \
      2>/dev/null) || log_err "No IP match CEPH_PUBLIC_NETWORK."
  fi
}

function verify_mon_folder {
  # Found monitor folder or leave.
  local MON_FOLDER_NUM=$(ls -d /var/lib/ceph/mon/*/ 2>/dev/null | grep "${CLUSTER}" | wc -w)
  if [ "${MON_FOLDER_NUM}" -eq 0 ]; then
    return 0
  elif [ -d /var/lib/ceph/mon/${CLUSTER}-${MON_NAME} ]; then
    return 0
  fi

  if [ "${MON_FOLDER_NUM}" -gt 1 ]; then
    log_err "More than one ceph monitor folders in /var/lib/ceph/mon/"
    exit 1
  else
    mv $(ls -d /var/lib/ceph/mon/*/) /var/lib/ceph/mon/${CLUSTER}-${MON_NAME}
    log_success "Renamed monitor folder in /var/lib/ceph/mon."
  fi
}

function verify_monmap {
  if [ ! -d /var/lib/ceph/mon/${CLUSTER}-${MON_NAME} ]; then
    return 0
  fi

  ceph-mon -i ${MON_NAME} --cluster ${CLUSTER} --extract-monmap /tmp/monmap &>/dev/null
  if monmaptool --print /tmp/monmap | grep -w "${MON_IP}" | grep -w -q "${MON_NAME}"; then
    return 0
  elif monmaptool --print /tmp/monmap | grep -w -q "mon.${MON_NAME}"; then
    monmaptool --rm ${MON_NAME} /tmp/monmap &>/dev/null
    log_success "Replaced MON_IP to ${MON_IP} in monmap"
  elif monmaptool --print /tmp/monmap | grep -w -q "${MON_IP}"; then
    local monname_in_monmap=$(monmaptool -p /tmp/monmap | grep -w "${MON_IP}" | \
      awk '{ sub ("mon.", "", $3); print $3}')
    monmaptool --rm ${monname_in_monmap} /tmp/monmap &>/dev/null
    log_success "Replaced MON_NAME to ${MON_NAME} in monmap"
  else
    log_success "Add ${MON_NAME} & ${MON_IP} to monmap."
  fi
  monmaptool --add ${MON_NAME} ${MON_IP}:6789 /tmp/monmap &>/dev/null
  ceph-mon -i ${MON_NAME} --cluster ${CLUSTER} --inject-monmap /tmp/monmap &>/dev/null
}


##################
# MON CONTROLLER #
##################

function mon_controller {
  mon_controller_env
  # making sure the root dirs are present
  : ${MAX_MONS:=3}
  etcdctl -C ${KV_IP}:${KV_PORT} mkdir ${CLUSTER_PATH} > /dev/null 2>&1 || true
  etcdctl -C ${KV_IP}:${KV_PORT} mkdir ${CLUSTER_PATH}/mon_host > /dev/null 2>&1  || true
  set_max_mon ${MAX_MONS} init

  # if svc & ep is running, than set mon_host
  if kubectl get ep ${EP_NAME} --server=${K8S_IP}:${K8S_PORT} ${K8S_CERT} --namespace=${NAMESPACE} &>/dev/null; then
    etcdctl -C ${KV_IP}:${KV_PORT} set ${CLUSTER_PATH}/global/mon_host ${EP_NAME}.${NAMESPACE}
  fi

  while [ true ]; do
    mon_controller_main
    sleep 60
  done
}

function mon_controller_main {
  # get $MAX_MONS & check it matching positive number
  if MAX_MONS=$(etcdctl -C ${KV_IP}:${KV_PORT} get ${CLUSTER_PATH}/max_mons); then
    if ! positive_num ${MAX_MONS}; then
      log_err "MAX_MONS type error: ${MAX_MONS}"
      return 0
    fi
  else
    log_err "Can't read max_mons"
  fi

  get_mon_nodes

  # how many mons needs to add?
  current_mons=$(echo ${nodes_have_mon_label} | wc -w)
  if [ ${current_mons} -lt "${MAX_MONS}" ]; then
    local mon_num2add=$(expr ${MAX_MONS} - ${current_mons})
  elif [ ${current_mons} -gt "${MAX_MONS}" ]; then
    local mon_num2add="-1"
  else
    local mon_num2add=0
  fi

  # create kubernetes mon label
  local counter=0
  if [ ${mon_num2add} == "-1" ]; then
    auto_remove_mon
  else
    local counter=0
    for mon2add in ${nodes_no_mon_label}; do
      if [ "${counter}" -lt ${mon_num2add} ]; then
        kubectl label node --server=${K8S_IP}:${K8S_PORT} ${K8S_CERT} ${mon2add} \
          ${MON_LABEL}=true --overwrite &>/dev/null && log_success "Add Mon node \"${mon2add}\""
        let counter=counter+1
      fi
    done
  fi

  # update endpoints
  if kubectl get ep ${EP_NAME} --server=${K8S_IP}:${K8S_PORT} ${K8S_CERT} --namespace=${NAMESPACE} &>/dev/null; then
    update_ceph_mon_ep
  fi
}

function get_mon_nodes {
  nodes_have_mon_label=$(kubectl get node --show-labels --server=${K8S_IP}:${K8S_PORT} ${K8S_CERT} \
    |  grep -w "${MON_LABEL}" | awk '/Ready/ { print $1 }')
  nodes_no_mon_label=$(kubectl get node --show-labels --server=${K8S_IP}:${K8S_PORT} ${K8S_CERT} \
    |  grep -wv "${MON_LABEL}" | awk '/Ready/ { print $1 }')
  etcd_mon_host=$(etcdctl -C ${KV_IP}:${KV_PORT} ls ${CLUSTER_PATH}/mon_host | sed "s#.*/mon_host/##")
}

function update_ceph_mon_ep {
  local ep_list=""
  for mon_name in $(echo ${etcd_mon_host}); do
    local mon_ip=$(mon_name_2_mon_ip ${mon_name})
    # josn form needs ","
    if [ -z "${mon_ip}" ]; then
      log_warn "Can't get mon_ip from ${mon_name}"
    elif [ -z "${ep_list}" ]; then
      local mon_ip_ep_format="{\"ip\": \"${mon_ip}\"}"
      ep_list=${mon_ip_ep_format}
    else
      local mon_ip_ep_format="{\"ip\": \"${mon_ip}\"}"
      ep_list="${ep_list}, ${mon_ip_ep_format}"
    fi
  done

  # make sure ep_list is not null
  if [ -n "${ep_list}" ]; then
    local UPDATE_EP="kubectl --server=${K8S_IP}:${K8S_PORT} ${K8S_CERT} \
       --namespace=${NAMESPACE} patch ep ${EP_NAME} -p \
      '{\"subsets\": [{\"addresses\": [${ep_list}],\"ports\": [{\"port\": 6789,\"protocol\": \"TCP\"}]}]}'"
    eval $UPDATE_EP >/dev/null
  fi
}

function node_ip_2_pod_name {
  if [ -z $1 ]; then
    log_err "Usage: node_ip_2_pod_name kubernetes_IP"
    exit 1
  fi
  kubectl get pod -o wide --namespace=${NAMESPACE} -l name=${POD_SELECTOR} | grep -w "$1" | awk '{ print $1 }'
}

function node_ip_2_hostname {
  if [ -z $1 ]; then
    log_err "Usage: node_ip_2_hostname kubernetes_IP"
    exit 1
  fi
  local pod_name=$(node_ip_2_pod_name $1)
  kubectl exec --namespace=${NAMESPACE} ${pod_name} hostname 2>/dev/null
}

function mon_name_2_mon_ip {
  if [ -z $1 ]; then
    log_err "Usage: mon_name_2_mon_ip mon_name"
    exit 1
  fi
  etcdctl -C ${KV_IP}:${KV_PORT} get ${CLUSTER_PATH}/mon_host/$1 2>/dev/null | sed 's/:6789//'
}

function remove_mon {
  if [ -z $1 ]; then
    log_err "Usage: remove_mon MON_name"
    exit 1
  fi
  get_ceph_admin
  get_mon_nodes
  if [ $(echo ${etcd_mon_host} | wc -w) -le $(get_max_mon) ]; then
    log_warn "Running Mon pods equals MAX_MONS. Do nothing."
    return 0
  fi
  for mon_node in ${nodes_have_mon_label}; do
    local mon_name=$(node_ip_2_hostname ${mon_node})
    if [ "$1" == "${mon_name}" ]; then
      etcdctl -C ${KV_IP}:${KV_PORT} rm ${CLUSTER_PATH}/mon_host/${mon_name} &>/dev/null || true
      kubectl label node --server=${K8S_IP}:${K8S_PORT} ${K8S_CERT} ${mon_node} \
        ${MON_LABEL}- &>/dev/null
      ceph mon remove "${mon_name}" || true
    fi
  done
  until confd -onetime -backend ${KV_TYPE} -node ${CONFD_NODE_SCHEMA}${KV_IP}:${KV_PORT} ${CONFD_KV_TLS} -prefix="/${CLUSTER_PATH}/" ; do
    echo "Waiting for confd to update templates..."
    sleep 1
  done
}

function auto_remove_mon {
  get_ceph_admin

  # get the last mon quorum index
  local mon_count=$(ceph quorum_status | jq .quorum | sed '1d;$d' | wc -w)
  local mon_quorum_json_index=$(expr ${mon_count} - 1)
  local mon_name2remove=$(ceph quorum_status | jq .quorum_names[${mon_quorum_json_index}] | tr -d "\"")
  if [ -z ${mon_name2remove} ]; then
    log_err "Monitor name not found"
    return 0
  elif [ "${mon_count}" -le 2 ]; then
    log_warn "Monitor number is too low. (Only \"${mon_count}\" monitor)"
    return 0
  else
    remove_mon ${mon_name2remove}
  fi
}

function set_max_mon {
  if [ $# -eq "2" ] && [ $2 == "init" ]; then
    local max_mon_num=$1
    etcdctl -C ${KV_IP}:${KV_PORT} mk ${CLUSTER_PATH}/max_mons ${max_mon_num} &>/dev/null || true
    return 0
  elif [ -z "$1" ]; then
    log_err "Usage: set_max_mon 1~5+"
    exit 1
  else
    local max_mon_num=$1
  fi
  if etcdctl -C ${KV_IP}:${KV_PORT} set ${CLUSTER_PATH}/max_mons ${max_mon_num}; then
    log_success "Expect MON number is \"$1\"."
  else
    log_err "Fail to set \$MAX_MONS"
    return 1
  fi
}

function get_max_mon {
  local MAX_MONS=""
  if MAX_MONS=$(etcdctl -C ${KV_IP}:${KV_PORT} get ${CLUSTER_PATH}/max_mons); then
    echo "${MAX_MONS}"
  else
    log_err "Fail to get \$MAX_MONS"
    return 1
  fi
}

