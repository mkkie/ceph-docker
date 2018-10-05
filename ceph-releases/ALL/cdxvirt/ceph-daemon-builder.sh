#!/bin/bash

: "${BUILDER_IMG:=cdxvirt/ceph-daemon-builder}"

function check_file {
  case ${FILE_TYPE} in
    socket)
      [ ! -S "${1}" ] && echo "Socket ${1} doesn't exist." && exit 1 ;;
    dir)
      [ ! -d "${1}" ] && echo "Directory ${1} doesn't exist." && exit 1 ;;
    *)
      [ ! -f "${1}" ] && echo "File ${1} doesn't exist." && exit 1 ;;
  esac
}

# MAIN
FILE_TYPE=socket check_file /var/run/docker.sock
check_file /bin/docker

if [ -n "${SRC_PATH}" ]; then
  SRC_DIR="-v ${SRC_PATH}:/ceph-container"
fi

docker run -it --privileged \
-v /var/run/docker.sock:/var/run/docker.sock \
-v /bin/docker:/bin/docker \
${SRC_DIR} \
${BUILDER_IMG} $@
