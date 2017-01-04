#! /bin/bash

: ${image:=cdxvirt/ceph-daemon:dev}
: ${OSD_FORCE_ZAP:=0}
: ${LOG_TIMEOUT:=10}
: ${DEBUG_MODE:=false}
: ${OSD_TMP_LOG:=osd-prepare.log}
: ${PATH_CEPH_CONF:=/etc/ceph}
: ${PATH_CEPH_DATA:=/var/lib/ceph}

CONT_ID=$(docker ps -q -f LABEL=CEPH=osd -f LABEL=OSD_DEVICE=${OSD_DEVICE})

function check_disk {
  if [ -z ${OSD_DEVICE} ]; then
    echo "OSD_DEVICE=/dev/sdx $0 [start|stop]"
    exit 1
  else
    sudo fdisk -l ${OSD_DEVICE} &>/dev/null || exit 2
  fi
}

function run_osd {
  if [ ! -z ${CONT_ID} ];then
    return 0
  fi
    
  if ! prepare_osd; then
    echo "Please check \"${OSD_DEVICE}\""
    echo " or use OSD_FORCE_ZAP=1 OSD_DEVICE=${OSD_DEVICE} $0 start"
    exit 3
  else
    activate_osd
  fi
}

function prepare_osd {
 echo "Preparing..."
 if docker run --privileged=true -v /dev/:/dev/ \
      --net=host --pid=host \
      -e DEBUG_MODE=${DEBUG_MODE} \
      -e OSD_DEVICE=${OSD_DEVICE} \
      -e OSD_TYPE=prepare \
      -e OSD_FORCE_ZAP=${OSD_FORCE_ZAP} \
      -v ${PATH_CEPH_CONF}:/etc/ceph \
      -v ${PATH_CEPH_DATA}:/var/lib/ceph/ \
      ${image} osd &>${OSD_TMP_LOG}; then
    return 0
  elif grep -q "You can also use the zap_device scenario on the appropriate device to zap it" ${OSD_TMP_LOG}; then
    return 0
  else 
    return 1
  fi
}

function activate_osd {
  CONT_ID=$(docker run --privileged=true -v /dev/:/dev/ \
    --net=host --pid=host \
    -l CEPH=osd -l OSD_DEVICE=${OSD_DEVICE} \
    -e DEBUG_MODE=${DEBUG_MODE} \
    -e OSD_DEVICE=${OSD_DEVICE} \
    -e OSD_TYPE=activate \
    -v ${PATH_CEPH_CONF}:/etc/ceph \
    -v ${PATH_CEPH_DATA}:/var/lib/ceph/ \
    -d ${image} osd | cut -c 1-12)
}

function check_activate {
  counter=0
  while [ ${counter} -le 10 ]; do
    if docker logs ${CONT_ID} 2>&1 | grep -q "No cluster conf"; then
      echo "Please check \"${OSD_DEVICE}\""
      echo " or use OSD_FORCE_ZAP=1 OSD_DEVICE=${OSD_DEVICE} $0 start"
      exit 4
    else
      let counter=counter+1
      sleep 1
    fi
  done
   timeout ${LOG_TIMEOUT} docker logs -f ${CONT_ID} || return 0
}

case $1 in
  stop)
    check_disk
    docker stop "${CONT_ID}"
    ;;
  stop-all)
    STOP_LIST=$(docker ps -q -f LABEL=CEPH=osd)
    if [ -n "${STOP_LIST}" ]; then
      docker stop ${STOP_LIST}
    fi
    ;;
  start)
    check_disk
    run_osd
    check_activate
    ;;
  list)
    docker ps -f LABEL=CEPH=osd
    ;;
  list-id)
    docker ps -q -f LABEL=CEPH=osd
    ;;
  *)
    ;;
esac
