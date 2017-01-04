#! /bin/bash

image=cdxvirt/ceph-daemon:dev
CONT_ID=$(docker ps -q -f LABEL=CEPH=mon)

function run_mon {
  if [ -z ${CONT_ID} ];then
    CONT_ID=$(docker run --privileged=true -v /dev/:/dev/ \
      --net=host --pid=host \
      -l CEPH=mon \
      -e OSD_JOURNAL_SIZE=2000 \
      -e DEBUG_MODE=false \
      -e CEPH_PUBLIC_NETWORK="192.168.32.0/23" \
      -e CEPH_CLUSTER_NETWORK="192.168.32.0/23" \
      -e NETWORK_AUTO_DETECT=5 \
      -v /etc/ceph:/etc/ceph \
      -v /var/lib/ceph/:/var/lib/ceph/ \
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
    timeout 30 docker logs -f ${CONT_ID} || return 0
    ;;
  bash)
    docker exec -it "${CONT_ID}" bash
    ;;
  initial)
    docker exec -it "${CONT_ID}" ceph osd crush rule create-simple replicated_type_osd default osd firstn
    docker exec -it "${CONT_ID}" ceph osd pool set rbd crush_ruleset 1
    docker exec -it "${CONT_ID}" ceph osd pool set rbd size 2
    ;;
  *)
    ;;
esac
