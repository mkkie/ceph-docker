#!/bin/bash

# KV PATH
: "${KV_PATH:="cdxvirt"}"
: "${OSD_KV_PATH:="${KV_PATH}/osd"}"
: "${MON_KV_PATH:="${KV_PATH}/mon"}"

# osd.sh
: "${RESERVED_SLOT:=}"
: "${MAX_OSD:=8}"
: "${FORCE_FORMAT:="LVM RAID"}"
