#!/bin/bash

: ${CLUSTER:=ceph}
CLUSTER_PATH=ceph-config/${CLUSTER}

# Add line "tunable chooseleaf_vary_r 1" into crushmap
if ceph health | grep -q "legacy tunables"; then
  ceph osd crush tunables jewel
fi

# Add key "/client/rbd_default_features" on ETCD
etcdctl mk ${CLUSTER_PATH}/client/rbd_default_features 3

# Add osd sortbitwise flag
ceph osd set sortbitwise
