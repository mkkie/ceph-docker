#!/bin/bash

: "${CLUSTER:=ceph}"
: "${NAMESPACE:=ceph}"
: "${RBD_KEY:=true}"

function ceph_conf_combined {
  kubectl create secret generic ceph-conf-combined --from-file=/etc/ceph/"${CLUSTER}".conf --from-file="${CLUSTER}".client.admin.keyring --from-file="${CLUSTER}".mon.keyring --namespace="${NAMESPACE}"
}

function ceph_conf {
  local fsid
  fsid=$(uuidgen)
  sed -r "s/@CLUSTER@/${CLUSTER:-ceph}/g" \
    /etc/confd/conf.d/ceph.conf.toml.in > /etc/confd/conf.d/ceph.conf.toml
  sed -i "s/by Confd/by Confd {{datetime}}/" /etc/confd/templates/ceph.conf.tmpl
  sed -i "s/@FSID@/${fsid}/" /cdx/ceph-conf-env.yaml
  if [ -n "${CEPH_PUBLIC_NETWORK}" ]; then
    sed -i "s#@CEPH_PUBLIC_NETWORK@#public_network: ${CEPH_PUBLIC_NETWORK}#" /cdx/ceph-conf-env.yaml
  else
    sed -i "s#@CEPH_PUBLIC_NETWORK@##" /cdx/ceph-conf-env.yaml
  fi
  if [ -n "${CEPH_CLUSTER_NETWORK}" ]; then
    sed -i "s#@CEPH_CLUSTER_NETWORK@#cluster_network: ${CEPH_CLUSTER_NETWORK}#" /cdx/ceph-conf-env.yaml
  else
    sed -i "s#@CEPH_CLUSTER_NETWORK@##" /cdx/ceph-conf-env.yaml
  fi
  confd -onetime -backend file -file /cdx/ceph-conf-env.yaml
  kubectl create secret generic ceph-conf-yaml --from-file=/cdx/ceph-conf-env.yaml --namespace="${NAMESPACE}"
}

function admin_key {
  ceph-authtool "${CLUSTER}".client.admin.keyring --gen-key --create-keyring -n client.admin --set-uid=0 --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow' --cap mgr 'allow *'
}

function mon_key {
  ceph-authtool "${CLUSTER}".mon.keyring --gen-key --create-keyring -n mon. --cap mon 'allow *'
}

function osd_boot_key {
  ceph-authtool "${CLUSTER}".osd.keyring --gen-key --create-keyring -n client.bootstrap-osd --cap mon 'allow profile bootstrap-osd'
  kubectl create secret generic "${CLUSTER}"-bootstrap-osd-keyring --from-file="${CLUSTER}".keyring="${CLUSTER}".osd.keyring --namespace="${NAMESPACE}"
}

function mds_boot_key {
  ceph-authtool "${CLUSTER}".mds.keyring --gen-key --create-keyring -n client.bootstrap-mds --cap mon 'allow profile bootstrap-mds'
  kubectl create secret generic "${CLUSTER}"-bootstrap-mds-keyring --from-file="${CLUSTER}".keyring="${CLUSTER}".mds.keyring --namespace="${NAMESPACE}"
}

function rgw_boot_key {
  ceph-authtool "${CLUSTER}".rgw.keyring --gen-key --create-keyring -n client.bootstrap-rgw --cap mon 'allow profile bootstrap-rgw'
  kubectl create secret generic "${CLUSTER}"-bootstrap-rgw-keyring --from-file="${CLUSTER}".keyring="${CLUSTER}".rgw.keyring --namespace="${NAMESPACE}"
}

function rbd_boot_key {
  ceph-authtool "${CLUSTER}".rbd.keyring --gen-key --create-keyring -n client.bootstrap-rbd --cap mon 'allow profile bootstrap-rbd'
  kubectl create secret generic "${CLUSTER}"-bootstrap-rbd-keyring --from-file="${CLUSTER}".keyring="${CLUSTER}".rbd.keyring --namespace="${NAMESPACE}"
}

function ceph_dns_conf {
  kubectl create secret generic ceph-dns-conf --from-file=resolv.conf=/cdx/ceph-dns.conf --namespace="${NAMESPACE}"
}

########
# MAIN #
########

ceph_conf
admin_key
mon_key
osd_boot_key
mds_boot_key
rgw_boot_key
rbd_boot_key
ceph_conf_combined
ceph_dns_conf
