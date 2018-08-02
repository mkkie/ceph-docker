#!/bin/bash
set -e

function cdx_entrypoint {
  CDX_CMD=$(echo ${1} | sed 's/cdx_//')
  case "${CDX_CMD}" in
    bash|*)
      shift
      exec $@
      ;;
  esac
}

