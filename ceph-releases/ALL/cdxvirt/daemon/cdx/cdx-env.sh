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

# dashboard
: "${DASHBOARD_USER:=vsdx}"
: "${DASHBOARD_PASSWORD:=vsdx}"

# K8S
: "${KUBECTL:=$(which kubectl)}"
: "${SECRET_DIR:=/k8s-secret}"
if [ -d "${SECRET_DIR}" ] && [ -n "$(ls -A ${SECRET_DIR})" ]; then
  mkdir -p /var/lib/ceph/bootstrap-{mds,osd,rbd,rgw}
  cp ${SECRET_DIR}/bootstrap-mds/ceph.keyring /var/lib/ceph/bootstrap-mds/
  cp ${SECRET_DIR}/bootstrap-osd/ceph.keyring /var/lib/ceph/bootstrap-osd/
  cp ${SECRET_DIR}/bootstrap-rbd/ceph.keyring /var/lib/ceph/bootstrap-rbd/
  cp ${SECRET_DIR}/bootstrap-rgw/ceph.keyring /var/lib/ceph/bootstrap-rgw/
  cp ${SECRET_DIR}/ceph/ceph.* /etc/ceph/
fi
