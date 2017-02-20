#!/bin/bash
set -e

function check_KV_IP {
  : ${K8S_NETWORK:=${CEPH_CLUSTER_NETWORK}}

  # search K8S_NETWORK first
  if K8S_IP=$(ip -4 -o a | awk '{ sub ("/..", "", $4); print $4 }' | grepcidr "$K8S_NETWORK") && \
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

sed -r "s/@CLUSTER@/${CLUSTER:-ceph}/g" \
    /etc/confd/conf.d/ceph.conf.toml.in > /etc/confd/conf.d/ceph.conf.toml

# make sure etcd uses http or https as a prefix
if [[ "$KV_TYPE" == "etcd" ]]; then
  if [ ! -z "${KV_CA_CERT}" ]; then
  	CONFD_NODE_SCHEMA="https://"
  else
    CONFD_NODE_SCHEMA="http://"
  fi
fi

function get_admin_key {
   kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/adminKeyring > /etc/ceph/${CLUSTER}.client.admin.keyring
}


function get_mon_config {

  CLUSTER_PATH=ceph-config/${CLUSTER}

  # making sure the root dirs are present for the confd to work with etcd
  if [[ "$KV_TYPE" == "etcd" ]]; then
    etcdctl mkdir ${CLUSTER_PATH}/auth > /dev/null 2>&1  || log "key already exists"
    etcdctl mkdir ${CLUSTER_PATH}/global > /dev/null 2>&1  || log "key already exists"
    etcdctl mkdir ${CLUSTER_PATH}/mon > /dev/null 2>&1  || log "key already exists"
    etcdctl mkdir ${CLUSTER_PATH}/mds > /dev/null 2>&1  || log "key already exists"
    etcdctl mkdir ${CLUSTER_PATH}/osd > /dev/null 2>&1  || log "key already exists"
    etcdctl mkdir ${CLUSTER_PATH}/client > /dev/null 2>&1  || log "key already exists"
  fi

  log "Adding Mon Host - ${MON_NAME}"
  kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/mon_host/${MON_NAME} ${MON_IP} > /dev/null 2>&1

  # Acquire lock to not run into race conditions with parallel bootstraps
  # FIXME: Use kviator to instead of etcdctl
  until etcdctl -C ${KV_IP}:${KV_PORT} mk ${CLUSTER_PATH}/lock $MON_NAME > /dev/null 2>&1 ; do
    log "Configuration is locked by another host. Waiting."
    sleep 1
  done

  # Update config after initial mon creation
  if kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/monSetupComplete > /dev/null 2>&1 ; then
    log "Configuration found for cluster ${CLUSTER}. Writing to disk."


    until confd -onetime -backend ${KV_TYPE} -node ${CONFD_NODE_SCHEMA}${KV_IP}:${KV_PORT} ${CONFD_KV_TLS} -prefix="/${CLUSTER_PATH}/" ; do
      log "Waiting for confd to update templates..."
      sleep 1
    done

    # Check/Create bootstrap key directories
    mkdir -p /var/lib/ceph/bootstrap-{osd,mds,rgw}

    log "Adding Keyrings"
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/monKeyring > /etc/ceph/${CLUSTER}.mon.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/adminKeyring > /etc/ceph/${CLUSTER}.client.admin.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/bootstrapOsdKeyring > /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/bootstrapMdsKeyring > /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/bootstrapRgwKeyring > /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring


    if [ ! -f /etc/ceph/monmap-${CLUSTER} ]; then
      log "Monmap is missing. Adding initial monmap..."
      kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/monmap | uudecode -o /etc/ceph/monmap-${CLUSTER}
    fi

    log "Trying to get the most recent monmap..."
    if timeout 5 ceph ${CEPH_OPTS} mon getmap -o /etc/ceph/monmap-${CLUSTER}; then
      log "Monmap successfully retrieved.  Updating KV store."
      uuencode /etc/ceph/monmap-${CLUSTER} - | kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/monmap -
    else
      log "Peers not found, using initial monmap."
    fi

  else
    # Create initial Mon, keyring
    log "No configuration found for cluster ${CLUSTER}. Generating."

    # Populate KV first
    populate_kv
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/osd/cluster_network ${CEPH_CLUSTER_NETWORK}
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/osd/public_network ${CEPH_PUBLIC_NETWORK}

    FSID=$(uuidgen)
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/auth/fsid ${FSID}

    until confd -onetime -backend ${KV_TYPE} -node ${CONFD_NODE_SCHEMA}${KV_IP}:${KV_PORT} ${CONFD_KV_TLS} -prefix="/${CLUSTER_PATH}/" ; do
      log "Waiting for confd to write initial templates..."
      sleep 1
    done

    log "Creating Keyrings"
    ceph-authtool /etc/ceph/${CLUSTER}.client.admin.keyring --create-keyring --gen-key -n client.admin --set-uid=0 --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow'
    ceph-authtool /etc/ceph/${CLUSTER}.mon.keyring --create-keyring --gen-key -n mon. --cap mon 'allow *'

    # Create bootstrap key directories
    mkdir -p /var/lib/ceph/bootstrap-{osd,mds,rgw}

    # Generate the OSD bootstrap key
    ceph-authtool /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring --create-keyring --gen-key -n client.bootstrap-osd --cap mon 'allow profile bootstrap-osd'

    # Generate the MDS bootstrap key
    ceph-authtool /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring --create-keyring --gen-key -n client.bootstrap-mds --cap mon 'allow profile bootstrap-mds'

    # Generate the RGW bootstrap key
    ceph-authtool /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring --create-keyring --gen-key -n client.bootstrap-rgw --cap mon 'allow profile bootstrap-rgw'


    log "Creating Monmap"
    monmaptool --create --add ${MON_NAME} "${MON_IP}:6789" --fsid ${FSID} /etc/ceph/monmap-${CLUSTER}

    log "Importing Keyrings and Monmap to KV"
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/monKeyring - < /etc/ceph/${CLUSTER}.mon.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/adminKeyring - < /etc/ceph/${CLUSTER}.client.admin.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/bootstrapOsdKeyring - < /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/bootstrapMdsKeyring - < /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/bootstrapRgwKeyring - < /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring

    uuencode /etc/ceph/monmap-${CLUSTER} - | kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/monmap -

    log "Completed initialization for ${MON_NAME}"
    kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} put ${CLUSTER_PATH}/monSetupComplete true > /dev/null 2>&1
  fi

  # Remove lock for other clients to install
  log "Removing lock for ${MON_NAME}"
  kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} del ${CLUSTER_PATH}/lock > /dev/null 2>&1

}

function get_config {

  CLUSTER_PATH=ceph-config/${CLUSTER}

  until kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/monSetupComplete > /dev/null 2>&1 ; do
    log "OSD: Waiting for monitor setup to complete..."
    sleep 5
  done

  until confd -onetime -backend ${KV_TYPE} -node ${CONFD_NODE_SCHEMA}${KV_IP}:${KV_PORT} ${CONFD_KV_TLS} -prefix="/${CLUSTER_PATH}/" ; do
    log "Waiting for confd to update templates..."
    sleep 1
  done

  # Check/Create bootstrap key directories
  mkdir -p /var/lib/ceph/bootstrap-{osd,mds,rgw}

  log "Adding bootstrap keyrings"
  kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/bootstrapOsdKeyring > /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring
  kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/bootstrapMdsKeyring > /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring
  kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} get ${CLUSTER_PATH}/bootstrapRgwKeyring > /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring

}
