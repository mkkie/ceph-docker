#!/bin/bash
set -e

source cdx/cdx-env.sh
source cdx/config-key.sh

function cdx_entrypoint {
  remove_tmp
  CDX_CMD=$(echo ${1} | sed 's/cdx_//')
  case "${CDX_CMD}" in
    bash)
      shift
      /bin/bash $@
      ;;
    mon)
      source cdx/mon.sh
      source start_mon.sh
      cdx_mon
      start_mon
      ;;
    osd)
      source cdx/osd.sh
      cdx_osd
      ;;
    osd_dev)
      source cdx/run-osd-dev.sh
      shift
      run_osd_dev $@
      ;;
    *)
      echo "See cdx/cdx.sh"
      ;;
  esac
}

function remove_tmp {
  # when source disk_list.sh, it create a tmp dir and does not remove it.
  rm -rf /var/lib/ceph/tmp/tmp.*
}
