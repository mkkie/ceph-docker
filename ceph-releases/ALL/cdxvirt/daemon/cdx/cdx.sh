#!/bin/bash
set -e

source /cdx/cdx-env.sh

function cdx_entrypoint {
  remove_tmp
  CDX_CMD=$(echo ${1} | sed 's/cdx_//')
  case "${CDX_CMD}" in
    bash)
      shift
      if [ -z "${1}" ]; then
        /bin/bash $@
      else
        $@
      fi
      ;;
    ceph_api)
      shift
      /cdx/ceph-api $@
      ;;
    mon)
      source /cdx/mon.sh
      source /start_mon.sh
      cdx_mon
      start_mon
      ;;
    osd)
      source /cdx/osd.sh
      cdx_osd
      ;;
    osd_dev)
      source /cdx/run-osd-dev.sh
      shift
      run_osd_dev $@
      ;;
    *)
      usage_exit
      ;;
  esac
}

function usage_exit {
  echo -e "cdx_entrypoint:"
  echo -e "\tcdx_bash\tExecute any command you want."
  echo -e "\tcdx_ceph_api\tExecute ceph-api to maintain ceph cluster."
  exit 1
}

function remove_tmp {
  # when source disk_list.sh, it create a tmp dir and does not remove it.
  rm -rf /var/lib/ceph/tmp/tmp.*
}
