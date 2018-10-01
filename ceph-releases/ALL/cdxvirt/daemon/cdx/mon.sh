#!/bin/bash
set -e

function get_mon_ip_from_public {
  if [ -n "${CEPH_PUBLIC_NETWORK}" ]; then
    MON_IP=$(ip -4 -o a | awk '{ sub ("/..", "", $4); print $4 }' | grepcidr "${CEPH_PUBLIC_NETWORK}" \
      2>/dev/null) || log "ERROR- No IP match CEPH_PUBLIC_NETWORK."
  fi
}

function create_ceph_ep {
  if ! ${KUBECTL} get ep -n ceph ceph-mon &>/dev/null; then
  cat <<ENDHERE > ceph-mon-ep.yaml
apiVersion: v1
kind: Endpoints
metadata:
  name: ceph-mon
  namespace: ceph
  labels:
    cdxvirt/cluster-service: "true"
subsets:
- addresses:
  - ip: ${MON_IP}
  ports:
  - port: 6789
    protocol: TCP
ENDHERE
  cat ceph-mon-ep.yaml | ${KUBECTL} create -f - && \
    log "Domain Name ceph-mon.ceph created." || sleep 2
  fi
}

## MAIN
function cdx_mon {
  # /etc/ceph could be update anytime. Store MONMAP to another place.
  MONMAP=/cdx/monmap
  MON_KEYRING=/cdx/${CLUSTER}.mon.keyring
  get_mon_ip_from_public
  create_ceph_ep
}
