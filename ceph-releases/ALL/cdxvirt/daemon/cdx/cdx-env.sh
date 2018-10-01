#!/bin/bash

# KV PATH
: "${KV_PATH:="cdxvirt"}"
: "${OSD_KV_PATH:="${KV_PATH}/osd"}"
: "${MON_KV_PATH:="${KV_PATH}/mon"}"
: "${CTRL_KV_PATH:="${KV_PATH}/ctrl"}"

# osd.sh
: "${RESERVED_SLOT:=}"
: "${MAX_OSD:=8}"
: "${FORCE_FORMAT:="LVM RAID"}"

# K8S
: "${NEW_KUBECONFIG:="/etc/kubernetes/kubeconfig-admin"}"
if $(which kubectl) get pod &>/dev/null; then
  KUBECTL=$(which kubectl)
else
  KUBECTL="$(which kubectl) --kubeconfig=${NEW_KUBECONFIG}"
fi
