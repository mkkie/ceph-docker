#!/bin/bash
set -e

function cdx_entrypoint {
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
  esac
}

