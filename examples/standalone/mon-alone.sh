#! /bin/bash

: ${image:=cdxvirt/ceph-daemon:dev}
: ${CEPH_PUBLIC_NETWORK:="192.168.32.0/23"}
: ${CEPH_CLUSTER_NETWORK:="192.168.32.0/23"}
: ${OSD_JOURNAL_SIZE:=2000}
: ${RC_SIZE:=2}
: ${LOG_TIMEOUT:=10}
: ${PATH_CEPH_CONF:=/etc/ceph}
: ${PATH_CEPH_DATA:=/var/lib/ceph}

CONT_ID=$(docker ps -q -f LABEL=CEPH=mon)

function run_mon {
  if [ -z ${CONT_ID} ];then
    CONT_ID=$(docker run --privileged=true -v /dev/:/dev/ \
      --net=host --pid=host \
      -l CEPH=mon \
      -e OSD_JOURNAL_SIZE=${OSD_JOURNAL_SIZE} \
      -e DEBUG_MODE=false \
      -e CEPH_PUBLIC_NETWORK=${CEPH_PUBLIC_NETWORK} \
      -e CEPH_CLUSTER_NETWORK=${CEPH_CLUSTER_NETWORK} \
      -e NETWORK_AUTO_DETECT=5 \
      -v ${PATH_CEPH_CONF}:/etc/ceph \
      -v ${PATH_CEPH_DATA}:/var/lib/ceph/ \
      -v /lib/modules:/lib/modules \
      -d ${image} mon | cut -c 1-12)
  fi
}

case $1 in
  stop)
    docker stop "${CONT_ID}"
    ;;
  start)
    run_mon
    timeout ${LOG_TIMEOUT} docker logs -f ${CONT_ID} || true
    ;;
  bash)
    docker exec -it "${CONT_ID}" bash
    ;;
  initial)
    docker exec -it "${CONT_ID}" ceph osd crush rule create-simple replicated_type_osd default osd firstn
    docker exec -it "${CONT_ID}" ceph osd pool set rbd crush_ruleset 1
    docker exec -it "${CONT_ID}" ceph osd pool set rbd size ${RC_SIZE}
    ;;
  *)
    ;;
esac
