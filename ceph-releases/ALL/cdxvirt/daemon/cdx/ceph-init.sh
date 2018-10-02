#!/bin/bash

: "${CLUSTER:=ceph}"
: "${NAMESPACE:=ceph}"
: "${RBD_KEY:=true}"
: "${KUBE_APISERVER:="https://10.0.0.1:443"}"
: "${NEW_KUBECONFIG:="/etc/kubernetes/kubeconfig-admin"}"
: "${CA_PATH:="/etc/kubernetes/ca.crt"}"
: "${TOKEN_PATH:="/etc/kubernetes/tokens/admin"}"
if $(which kubectl) get pod &>/dev/null; then
  KUBECTL=$(which kubectl)
else
  KUBECTL="$(which kubectl) --kubeconfig=${NEW_KUBECONFIG}"
fi


function k8s_key {
  if ${KUBECTL} get pod &>/dev/null; then
    return 0
  fi
  TOKEN=$(cat ${TOKEN_PATH})
  $(which kubectl) config set-cluster local --certificate-authority="${CA_PATH}" \
    --embed-certs=true --server="${KUBE_APISERVER}" --kubeconfig="${NEW_KUBECONFIG}"
  $(which kubectl) config set-credentials admin-user \
    --token="${TOKEN}" --kubeconfig="${NEW_KUBECONFIG}"
  $(which kubectl) config set-context default \
  --cluster=local --user=admin-user --kubeconfig="${NEW_KUBECONFIG}"
  $(which kubectl) config use-context default --kubeconfig="${NEW_KUBECONFIG}"
  $(which kubectl) --kubeconfig="${NEW_KUBECONFIG}" create secret generic k8s-key --from-file="${NEW_KUBECONFIG}" --namespace="${NAMESPACE}"
}

function ceph_conf_combined {
  ${KUBECTL} create secret generic ceph-conf-combined --from-file=/etc/ceph/"${CLUSTER}".conf --from-file="${CLUSTER}".client.admin.keyring --from-file="${CLUSTER}".mon.keyring --namespace="${NAMESPACE}"
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
  ${KUBECTL} create secret generic ceph-conf-yaml --from-file=/cdx/ceph-conf-env.yaml --namespace="${NAMESPACE}"
}

function admin_key {
  ceph-authtool "${CLUSTER}".client.admin.keyring --gen-key --create-keyring -n client.admin --set-uid=0 --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow' --cap mgr 'allow *'
}

function mon_key {
  ceph-authtool "${CLUSTER}".mon.keyring --gen-key --create-keyring -n mon. --cap mon 'allow *'
}

function osd_boot_key {
  ceph-authtool "${CLUSTER}".osd.keyring --gen-key --create-keyring -n client.bootstrap-osd --cap mon 'allow profile bootstrap-osd'
  ${KUBECTL} create secret generic "${CLUSTER}"-bootstrap-osd-keyring --from-file="${CLUSTER}".keyring="${CLUSTER}".osd.keyring --namespace="${NAMESPACE}"
}

function mds_boot_key {
  ceph-authtool "${CLUSTER}".mds.keyring --gen-key --create-keyring -n client.bootstrap-mds --cap mon 'allow profile bootstrap-mds'
  ${KUBECTL} create secret generic "${CLUSTER}"-bootstrap-mds-keyring --from-file="${CLUSTER}".keyring="${CLUSTER}".mds.keyring --namespace="${NAMESPACE}"
}

function rgw_boot_key {
  ceph-authtool "${CLUSTER}".rgw.keyring --gen-key --create-keyring -n client.bootstrap-rgw --cap mon 'allow profile bootstrap-rgw'
  ${KUBECTL} create secret generic "${CLUSTER}"-bootstrap-rgw-keyring --from-file="${CLUSTER}".keyring="${CLUSTER}".rgw.keyring --namespace="${NAMESPACE}"
}

function rbd_boot_key {
  ceph-authtool "${CLUSTER}".rbd.keyring --gen-key --create-keyring -n client.bootstrap-rbd --cap mon 'allow profile bootstrap-rbd'
  ${KUBECTL} create secret generic "${CLUSTER}"-bootstrap-rbd-keyring --from-file="${CLUSTER}".keyring="${CLUSTER}".rbd.keyring --namespace="${NAMESPACE}"
}

########
# MAIN #
########

k8s_key
ceph_conf
admin_key
mon_key
osd_boot_key
mds_boot_key
rgw_boot_key
rbd_boot_key
ceph_conf_combined
