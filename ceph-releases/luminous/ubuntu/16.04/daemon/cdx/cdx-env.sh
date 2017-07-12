#!/bin/bash

: "${KV_TYPE:=etcd}"
: "${KV_IP:=127.0.0.1}"
: "${KV_PORT:=2379}"
: "${OSD_BLUESTORE:=1}"
: "${MAX_OSDS:=3}"
