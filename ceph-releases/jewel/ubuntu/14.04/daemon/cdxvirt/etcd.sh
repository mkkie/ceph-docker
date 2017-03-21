#!/bin/bash

########
# ETCD #
########

CLUSTER_PATH=ceph-config/${CLUSTER}

function check_KV_IP {
  : ${K8S_NETWORK:=${CEPH_CLUSTER_NETWORK}}

  # search K8S_NETWORK first
  if K8S_IP=$(ip -4 -o a | awk '{ sub ("/..", "", $4); print $4 }' | grepcidr "$K8S_NETWORK" 2>/dev/null) && \
    curl http://"${K8S_IP}":"${KV_PORT}" &>/dev/null; then
    KV_IP=${K8S_IP}
    return 0
  else
    K8S_IP=""
  fi

  # if K8S_IP can't connect to ETCD then search FLANNEL_NETWORK
  local flannel_gw=$(route -n | awk '/UG/ {print $2 }' | head -n 1)
  if curl http://${flannel_gw}:${KV_PORT} &>/dev/null; then
    KV_IP=${flannel_gw}
    return 0
  fi

  # Use KV_IP default value
  if curl http://${KV_IP}:${KV_PORT} &>/dev/null; then
    return 0
  else
    log_err "Can't connect to ETCD Server. Please check the following settings: "
    log_err "\$K8S_NETWORK=${K8S_NETWORK}"
    log_err "\$KV_IP=${KV_IP}"
    exit 1
  fi
}

######################
# HIDE INFO OF CONFD #
######################

function confd {
  command confd $@ &>/dev/null
}
